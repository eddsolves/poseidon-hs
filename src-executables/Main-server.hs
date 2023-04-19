{-# LANGUAGE OverloadedStrings #-}

import           Poseidon.GenotypeData        (GenotypeDataSpec (..))
import           Poseidon.Janno               (JannoList (..), JannoRow (..))
import           Poseidon.Package             (PackageReadOptions (..),
                                               PoseidonPackage (..),
                                               defaultPackageReadOptions,
                                               readPoseidonPackageCollection)
import           Poseidon.SecondaryTypes      (GroupInfo (..),
                                               IndividualInfo (..),
                                               PackageInfo (..),
                                               ServerApiReturnType(..),
                                               ApiReturnData(..))
import           Poseidon.Utils               (LogMode (..), PoseidonLogIO,
                                               logInfo, usePoseidonLogger)

import           Codec.Archive.Zip            (Archive, addEntryToArchive,
                                               emptyArchive, fromArchive,
                                               toEntry)
import           Control.Applicative          (optional)
import           Control.Monad                (forM, unless, when)
import           Control.Monad.IO.Class       (liftIO)
import qualified Data.ByteString.Lazy         as B
import           Data.List                    (group, nub, sortOn)
import Data.Maybe (maybeToList)
import qualified Data.Text                    as TS
import           Data.Text.Lazy               (Text, intercalate, pack, unpack)
import           Data.Text.Lazy.Encoding      (decodeUtf8)
import           Data.Time.Clock.POSIX        (utcTimeToPOSIXSeconds)
import           Data.Version                 (parseVersion, showVersion, Version, makeVersion)
import           Network.Wai                  (Request, pathInfo, queryString)
import           Network.Wai.Handler.Warp     (defaultSettings, run, setPort)
import           Network.Wai.Handler.WarpTLS  (runTLS, tlsSettings,
                                               tlsSettingsChain)
import           Network.Wai.Middleware.Cors  (simpleCors)
import qualified Options.Applicative          as OP
import           Paths_poseidon_hs            (version)
import           System.Directory             (createDirectoryIfMissing,
                                               doesFileExist,
                                               getModificationTime)
import           System.FilePath              ((<.>), (</>))
import           Text.ParserCombinators.ReadP (readP_to_S)
import           Web.Scotty                   (ScottyM, file, get, html, json, ActionM,
                                               middleware, notFound, param, function,
                                               raise, scottyApp, text, Param, rescue, params)

data CommandLineOptions = CommandLineOptions
    { cliBaseDirs        :: [FilePath]
    , cliZipDir          :: FilePath
    , cliPort            :: Int
    , cliIgnoreGenoFiles :: Bool
    , cliIgnoreChecksums :: Bool
    , cliCertFiles       :: Maybe (FilePath, [FilePath], FilePath)
    }
    deriving (Show)

main :: IO ()
main = usePoseidonLogger VerboseLog $ do
    logInfo "Server starting up. Loading packages..."
    CommandLineOptions baseDirs zipPath port ignoreGenoFiles ignoreChecksums certFiles <- liftIO $
        OP.customExecParser (OP.prefs OP.showHelpOnEmpty) optParserInfo
    let pacReadOpts = defaultPackageReadOptions {
              _readOptStopOnDuplicates = True
            , _readOptIgnoreChecksums  = ignoreChecksums
            , _readOptGenoCheck        = ignoreGenoFiles
        }
    allPackages <- readPoseidonPackageCollection pacReadOpts baseDirs
    logInfo "Checking whether zip files are missing or outdated"
    liftIO $ createDirectoryIfMissing True zipPath
    zipDict <- if ignoreGenoFiles then return [] else forM allPackages (\pac -> do
        let fn = zipPath </> posPacTitle pac <.> "zip"
        zipFileOutdated <- liftIO $ checkZipFileOutdated pac fn ignoreGenoFiles
        when zipFileOutdated $ do
            logInfo ("Zip Archive for package " ++ posPacTitle pac ++ " missing or outdated. Zipping now")
            zip_ <- liftIO $ makeZipArchive pac ignoreGenoFiles
            let zip_raw = fromArchive zip_
            liftIO $ B.writeFile fn zip_raw
        return (posPacTitle pac, fn))
    let runScotty = case certFiles of
            Nothing                              -> scottyHTTP  port
            Just (certFile, chainFiles, keyFile) -> scottyHTTPS port certFile chainFiles keyFile
    runScotty $ do
        middleware simpleCors

        -- API for retreiving package zip files
        unless ignoreGenoFiles . get "/zip_file/:package_name" $ do
            p_ <- param "package_name"
            let zipFN = lookup (unpack p_) zipDict
            case zipFN of
                Just fn -> file fn
                Nothing -> raise ("unknown package " <> p_)

        -- API for version output
        get "/server_version" $
            text . pack . showVersion $ version

        get "/packages" . conditionOnClientVersion $
            let retData = ApiReturnPackageInfo . map packageToPackageInfo $ allPackages
            in  return $ ServerApiReturnType (Just retData) []
        get "/groups" . conditionOnClientVersion $
            let retData = ApiReturnGroupInfo . getAllGroupInfo $ allPackages
            in  return $ ServerApiReturnType (Just retData) []
        get "/individuals" $
            let retData = ApiReturnIndividualInfo . getAllIndividualInfo $ allPackages
            in  return $ ServerApiReturnType (Just retData) []
        get "/janno" . conditionOnClientVersion $
            let retData = ApiReturnJanno . getAllPacJannoPairs $ allPackages
            in  return $ ServerApiReturnType (Just retData) []

        notFound $ raise "Unknown request"

conditionOnClientVersion :: ActionM ServerApiReturnType -> ActionM ()
conditionOnClientVersion contentAction = do
    maybeClientVersion <- (Just <$> param "client_version") `rescue` (\_ -> return Nothing)
    (clientVersion, versionWarnings) <- case maybeClientVersion of
        Nothing            -> return (version, ["No client_version passed. Assuming latest version " ++ showVersion version])
        Just versionString -> case parseVersionString versionString of
            Just v -> return (v, [])
            Nothing -> return (version, ["Could not parse Client Version string " ++ unpack versionString ++ ", assuming latest version " ++ showVersion version])
    if clientVersion < minimalRequiredClientVersion then do
        let msg = "This Server API requires trident version at least " ++ show minimalRequiredClientVersion ++
                "Please go to https://poseidon-framework.github.io/#/trident and update your trident installation."
        json $ ServerApiReturnType (versionWarnings ++ [msg]) Nothing
    else do
        ServerApiReturnType content messages <- contentAction
        json $ ServerApiReturnType (versionWarnings ++ messages) content

minimalRequiredClientVersion :: Version
minimalRequiredClientVersion = makeVersion [1, 1, 8, 5]

parseVersionString :: Text -> Maybe Version
parseVersionString vText = case filter ((=="") . snd) $ readP_to_S parseVersion (unpack vText) of
    [(v', "")] -> Just v'
    _          -> Nothing

optParserInfo :: OP.ParserInfo CommandLineOptions
optParserInfo = OP.info (OP.helper <*> versionOption <*> optParser) (
    OP.briefDesc <>
    OP.progDesc "poseidon-http-server is a HTTP Server to provide information about \
        \Poseidon package repositories. \
        \More information: \
        \https://github.com/poseidon-framework/poseidon-hs. \
        \Report issues: \
        \https://github.com/poseidon-framework/poseidon-hs/issues")

versionOption :: OP.Parser (a -> a)
versionOption = OP.infoOption (showVersion version) (OP.long "version" <> OP.help "Show version")

optParser :: OP.Parser CommandLineOptions
optParser = CommandLineOptions <$> parseBasePaths <*> parseZipDir <*> parsePort <*> parseIgnoreGenoFiles <*> parseIgnoreChecksums <*> parseMaybeCertFiles

parseBasePaths :: OP.Parser [FilePath]
parseBasePaths = OP.some (OP.strOption (OP.long "baseDir" <>
    OP.short 'd' <>
    OP.metavar "DIR" <>
    OP.help "a base directory to search for Poseidon Packages"))

parseZipDir :: OP.Parser FilePath
parseZipDir = OP.strOption (OP.long "zipDir" <>
    OP.short 'z' <>
    OP.metavar "DIR" <>
    OP.help "a directory to store Zip files in")

parsePort :: OP.Parser Int
parsePort = OP.option OP.auto (OP.long "port" <> OP.short 'p' <> OP.metavar "PORT" <>
    OP.value 3000 <> OP.showDefault <>
    OP.help "the port on which the server listens")

parseIgnoreGenoFiles :: OP.Parser Bool
parseIgnoreGenoFiles = OP.switch (OP.long "ignoreGenoFiles" <> OP.short 'i' <>
    OP.help "whether to ignore the bed and SNP files. Useful for debugging")

parseIgnoreChecksums :: OP.Parser Bool
parseIgnoreChecksums = OP.switch (OP.long "ignoreChecksums" <> OP.short 'c' <>
    OP.help "whether to ignore checksums. Useful for speedup in debugging")

parseMaybeCertFiles :: OP.Parser (Maybe (FilePath, [FilePath], FilePath))
parseMaybeCertFiles = optional parseFiles
  where
    parseFiles = (,,) <$> parseCertFile <*> OP.many parseChainFile <*> parseKeyFile

parseKeyFile :: OP.Parser FilePath
parseKeyFile = OP.strOption (OP.long "keyFile" <> OP.metavar "KEYFILE" <>
                             OP.help "The key file of the TLS Certificate used for HTTPS")

parseChainFile :: OP.Parser FilePath
parseChainFile = OP.strOption (OP.long "chainFile" <> OP.metavar "CHAINFILE" <>
                               OP.help "The chain file of the TLS Certificate used for HTTPS. Can be given multiple times")

parseCertFile :: OP.Parser FilePath
parseCertFile = OP.strOption (OP.long "certFile" <> OP.metavar "CERTFILE" <>
                              OP.help "The cert file of the TLS Certificate used for HTTPS")

checkZipFileOutdated :: PoseidonPackage -> FilePath -> Bool -> IO Bool
checkZipFileOutdated pac fn ignoreGenoFiles = do
    zipFileExists <- doesFileExist fn
    if zipFileExists
    then do
        zipModTime <- getModificationTime fn
        yamlOutdated <- checkOutdated zipModTime (posPacBaseDir pac </> "POSEIDON.yml")
        bibOutdated <- case posPacBibFile pac of
            Just fn_ -> checkOutdated zipModTime (posPacBaseDir pac </> fn_)
            Nothing  -> return False
        jannoOutdated <- case posPacJannoFile pac of
            Just fn_ -> checkOutdated zipModTime (posPacBaseDir pac </> fn_)
            Nothing  -> return False
        readmeOutdated <- case posPacReadmeFile pac of
            Just fn_ -> checkOutdated zipModTime (posPacBaseDir pac </> fn_)
            Nothing  -> return False
        changelogOutdated <- case posPacChangelogFile pac of
            Just fn_ -> checkOutdated zipModTime (posPacBaseDir pac </> fn_)
            Nothing  -> return False
        let gd = posPacGenotypeData pac
        genoOutdated <- if ignoreGenoFiles then return False else checkOutdated zipModTime (posPacBaseDir pac </> genoFile gd)
        snpOutdated <- if ignoreGenoFiles then return False else checkOutdated zipModTime (posPacBaseDir pac </> snpFile gd)
        indOutdated <- if ignoreGenoFiles then return False else checkOutdated zipModTime (posPacBaseDir pac </> indFile gd)
        return $ or [yamlOutdated, bibOutdated, jannoOutdated, readmeOutdated, changelogOutdated, genoOutdated, snpOutdated, indOutdated]
    else
        return True
  where
    checkOutdated zipModTime fn_ = (> zipModTime) <$> getModificationTime fn_

makeZipArchive :: PoseidonPackage -> Bool -> IO Archive
makeZipArchive pac ignoreGenoFiles =
    addYaml emptyArchive >>= addJanno >>= addBib >>= addReadme >>= addChangelog >>= addInd >>= addSnp >>= addGeno
  where
    addYaml = addFN "POSEIDON.yml" (posPacBaseDir pac)
    addJanno = case posPacJannoFile pac of
        Nothing -> return
        Just fn -> addFN fn (posPacBaseDir pac)
    addBib = case posPacBibFile pac of
        Nothing -> return
        Just fn -> addFN fn (posPacBaseDir pac)
    addReadme = case posPacReadmeFile pac of
        Nothing -> return
        Just fn -> addFN fn (posPacBaseDir pac)
    addChangelog = case posPacChangelogFile pac of
        Nothing -> return
        Just fn -> addFN fn (posPacBaseDir pac)
    addInd = addFN (indFile . posPacGenotypeData $ pac) (posPacBaseDir pac)
    addSnp = if ignoreGenoFiles
             then return
             else addFN (snpFile . posPacGenotypeData $ pac) (posPacBaseDir pac)
    addGeno = if ignoreGenoFiles
              then return
              else addFN (genoFile . posPacGenotypeData $ pac) (posPacBaseDir pac)
    addFN :: FilePath -> FilePath -> Archive -> IO Archive
    addFN fn baseDir a = do
        let fullFN = baseDir </> fn
        raw <- B.readFile fullFN
        modTime <- round . utcTimeToPOSIXSeconds <$> getModificationTime fullFN
        let zipEntry = toEntry fn modTime raw
        return (addEntryToArchive zipEntry a)

scottyHTTPS :: Int -> FilePath -> [FilePath] -> FilePath -> ScottyM () -> PoseidonLogIO ()
scottyHTTPS port cert chains key s = do
    -- this is just the same output as with scotty, to make it consistent whether or not using https
    logInfo $ "Server now listening via HTTPS on " ++ show port
    let tsls = case chains of
            [] -> tlsSettings cert key
            c  -> tlsSettingsChain cert c key
    liftIO $ do
        app <- liftIO $ scottyApp s
        runTLS tsls (setPort port defaultSettings) app

scottyHTTP :: Int -> ScottyM () -> PoseidonLogIO ()
scottyHTTP port s = do
    logInfo $ "Server now listening via HTTP on " ++ show port
    liftIO $ do
        app <- scottyApp s
        run port app

getAllPacJannoPairs :: [PoseidonPackage] -> [(String, [JannoRow])]
getAllPacJannoPairs packages = [(posPacTitle pac, posPacJanno pac) | pac <- packages]

getAllIndividualInfo :: [PoseidonPackage] -> [IndividualInfo]
getAllIndividualInfo packages = do
    pac <- packages
    jannoRow <- posPacJanno pac
    let name = jPoseidonID jannoRow
        groups = getJannoList . jGroupName $ jannoRow
        pacName = posPacTitle pac
    return $ IndividualInfo name groups pacName

getAllGroupInfo :: [PoseidonPackage] -> [GroupInfo]
getAllGroupInfo packages = do
    let unnestedPairs = do
            IndividualInfo _ groups pacName <- getAllIndividualInfo packages
            group_ <- groups
            return (group_, pacName)
    let groupedPairs = group . sortOn fst $ unnestedPairs
    group_ <- groupedPairs
    let groupName = head . map fst $ group_
        groupPacs = nub . map snd $ group_
        groupNrInds = length group_
    return $ GroupInfo groupName groupPacs groupNrInds


packageToPackageInfo :: PoseidonPackage -> PackageInfo
packageToPackageInfo pac = PackageInfo {
    pTitle         = posPacTitle pac,
    pVersion       = posPacPackageVersion pac,
    pPosVersion    = posPacPoseidonVersion pac,
    pDescription   = posPacDescription pac,
    pLastModified  = posPacLastModified pac,
    pNrIndividuals = (length . posPacJanno) pac
}
