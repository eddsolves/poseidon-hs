{-# LANGUAGE OverloadedStrings #-}

module Poseidon.Chronicle where

import           Poseidon.Package        (PoseidonPackage (..))
import           Poseidon.SecondaryTypes (VersionComponent (..),
                                          updateThreeComponentVersion)
import           Poseidon.Utils          (PoseidonException (..), PoseidonIO)

import           Control.Monad.Catch     (throwM)
import           Control.Monad.IO.Class  (liftIO)
import           Data.Aeson              (FromJSON, ToJSON, object, parseJSON,
                                          toJSON, withObject, (.!=), (.:),
                                          (.:?), (.=))
import qualified Data.ByteString         as B
import           Data.Function           (on)
import           Data.List               (elemIndex)
import           Data.Maybe              (fromMaybe)
import qualified Data.Set                as S
import           Data.Time               (Day, UTCTime (..), getCurrentTime)
import           Data.Version            (Version, makeVersion)
import           Data.Yaml               (decodeEither')
import           Data.Yaml.Pretty        (defConfig, encodePretty,
                                          setConfCompare, setConfDropNull)
import           GitHash                 (getGitInfo, giHash)
import           System.Directory        (createDirectoryIfMissing,
                                          makeAbsolute)
import           System.FilePath         (takeDirectory)

data PoseidonPackageChronicle = PoseidonPackageChronicle
    { snapYamlTitle            :: Maybe String
    , snapYamlDescription      :: Maybe String
    , snapYamlChronicleVersion :: Maybe Version
    , snapYamlLastModified     :: Maybe Day
    , snapYamlPackages         :: [PackageState]
    }
    deriving (Show, Eq)

instance FromJSON PoseidonPackageChronicle where
    parseJSON = withObject "PoseidonYamlStruct" $ \v -> PoseidonPackageChronicle
        <$> v .:? "title"
        <*> v .:? "description"
        <*> v .:? "chronicleVersion"
        <*> v .:? "lastModified"
        <*> v .:? "packages" .!= []

instance ToJSON PoseidonPackageChronicle where
    toJSON x = object $ [
        "title"            .= snapYamlTitle x,
        "description"      .= snapYamlDescription x] ++
        ["chronicleVersion" .= snapYamlChronicleVersion x,
        "lastModified"     .= snapYamlLastModified x] ++
        if not $ null (snapYamlPackages x) then ["packages" .= snapYamlPackages x] else []

-- | A data type to represent a package state
data PackageState = PackageState
    { pacStateTitle   :: String        -- ^ the title of the package
    , pacStateVersion :: Maybe Version -- ^ the version of the package
    , pacStateCommit  :: String        -- ^ the hash of a relevant commit where a package can be accessed in this version
    }
    deriving (Show)

instance Eq PackageState where
    (PackageState t1 v1 _) == (PackageState t2 v2 _) = (t1 == t2) && (v1 == v2)

instance Ord PackageState where
    (PackageState t1 v1 _) `compare` (PackageState t2 v2 _) = (t1,v1) `compare` (t2,v2)

instance FromJSON PackageState where
    parseJSON = withObject "packages" $ \v -> PackageState
        <$> v .:  "title"
        <*> v .:? "version"
        <*> v .:  "commit"

instance ToJSON PackageState where
    toJSON x = object [
          "title"   .= pacStateTitle x
        , "version" .= pacStateVersion x
        , "commit"  .= pacStateCommit x
        ]

updateChronicle :: PoseidonPackageChronicle -> PoseidonPackageChronicle -> PoseidonPackageChronicle
updateChronicle oldChronicle newChronicle =
    let oldPackageSet = S.fromList $ snapYamlPackages oldChronicle
        newPackageSet = S.fromList $ snapYamlPackages newChronicle
        updatedPacSet = updatePackageSet oldPackageSet newPackageSet
        oldVersion = snapYamlChronicleVersion oldChronicle
    in PoseidonPackageChronicle {
      snapYamlTitle           = snapYamlTitle oldChronicle
    , snapYamlDescription     = snapYamlDescription oldChronicle
    , snapYamlChronicleVersion = if updatedPacSet /= oldPackageSet
                                then case oldVersion of
                                    Just v -> Just $ updateThreeComponentVersion Minor v
                                    Nothing -> Nothing
                                else oldVersion
    , snapYamlLastModified    = snapYamlLastModified newChronicle
    , snapYamlPackages        = S.toList updatedPacSet
    }
    where
        -- note that package comparison ignores git commits
        updatePackageSet :: S.Set PackageState -> S.Set PackageState -> S.Set PackageState
        updatePackageSet oldPacs newPacs =
            -- this implementation makes sure that the entries for old packages are kept around
            let oldNotInNew = oldPacs S.\\ newPacs
                goodOld = oldPacs S.\\ oldNotInNew
                newNotInOld = newPacs S.\\ goodOld
            in goodOld <> oldNotInNew <> newNotInOld

readChronicle :: FilePath -> PoseidonIO PoseidonPackageChronicle
readChronicle p = do
    bs <- liftIO $ B.readFile p
    case decodeEither' bs of
        Left err   -> throwM $ PoseidonYamlParseException p err
        Right snap -> return snap

writeChronicle :: FilePath -> PoseidonPackageChronicle -> PoseidonIO ()
writeChronicle p snapShot = do
    liftIO $ createDirectoryIfMissing True $ takeDirectory p
    liftIO $ B.writeFile p (encodePretty opts snapShot)
    where
        opts = setConfDropNull True $ setConfCompare (compare `on` fieldIndex) defConfig
        fieldIndex s = fromMaybe (length fields) $ s `elemIndex` fields
        fields = [
            "title",
            "description",
            "contributor",
            "name",
            "email",
            "orcid",
            "chronicleVersion",
            "lastModified",
            "packages",
            "title",
            "version",
            "commit"
         ]

makeChronicle :: [PoseidonPackage] -> PoseidonIO PoseidonPackageChronicle
makeChronicle pacs = do
    snap <- makeMinimalChronicle pacs
    (UTCTime today _) <- liftIO getCurrentTime
    return $ snap {
      snapYamlTitle           = Just "Chronicle title"
    , snapYamlDescription     = Just "Chronicle description"
    , snapYamlChronicleVersion = Just $ makeVersion [0, 1, 0]
    , snapYamlLastModified    = Just today
    }

makeMinimalChronicle :: [PoseidonPackage] -> PoseidonIO PoseidonPackageChronicle
makeMinimalChronicle pacs = do
    pacChronicles <- chroniclePackages pacs
    return $ PoseidonPackageChronicle {
      snapYamlTitle           = Nothing
    , snapYamlDescription     = Nothing
    , snapYamlChronicleVersion = Nothing
    , snapYamlLastModified    = Nothing
    , snapYamlPackages        = pacChronicles
    }

chroniclePackages :: [PoseidonPackage] -> PoseidonIO [PackageState]
chroniclePackages = mapM snapOne
    where
        snapOne :: PoseidonPackage -> PoseidonIO PackageState
        snapOne pac = do
            commit <- getGitCommitHash $ posPacBaseDir pac
            return $ PackageState {
                pacStateTitle   = posPacTitle pac,
                pacStateVersion = posPacPackageVersion pac,
                pacStateCommit  = commit
            }
        getGitCommitHash :: FilePath -> PoseidonIO String
        getGitCommitHash p = do
            eitherCommit <- liftIO $ getGitInfo p
            case eitherCommit of
                Left _ -> do
                    pAbsolute <- liftIO $ makeAbsolute p
                    let oneLevelUp = takeDirectory pAbsolute
                    if oneLevelUp == takeDirectory oneLevelUp
                    then do
                        throwM $ PoseidonGitException $ "Did not find .git directory in or above " ++ show p
                    else getGitCommitHash oneLevelUp
                Right info -> do
                    return $ giHash info

