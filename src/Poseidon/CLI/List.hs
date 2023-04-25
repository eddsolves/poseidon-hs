{-# LANGUAGE OverloadedStrings #-}

module Poseidon.CLI.List (runList, ListOptions(..), ListEntity(..), RepoLocationSpec(..)) where

import           Poseidon.Package        (PackageReadOptions (..),
                                          defaultPackageReadOptions,
                                          getAllGroupInfo,
                                          getExtendedIndividualInfo,
                                          packageToPackageInfo,
                                          readPoseidonPackageCollection)
import           Poseidon.SecondaryTypes (ApiReturnData (..), GroupInfo (..),
                                          IndividualInfo (..), PackageInfo (..),
                                          processApiResponse)
import           Poseidon.Utils          (PoseidonIO, extendNameWithVersion,
                                          logInfo, logWarning)

import           Control.Monad           (forM_, when)
import           Control.Monad.IO.Class  (liftIO)
import           Data.List               (intercalate, sortOn)
import           Data.Maybe              (catMaybes, fromMaybe)
import           Data.Version            (showVersion)
import           Text.Layout.Table       (asciiRoundS, column, def, expandUntil,
                                          rowsG, tableString, titlesH)

-- | A datatype representing command line options for the list command
data ListOptions = ListOptions
    { _listRepoLocation :: RepoLocationSpec -- ^ the list of base directories to search for packages
    , _listListEntity   :: ListEntity -- ^ what to list
    , _listRawOutput    :: Bool -- ^ whether to output raw TSV instead of a nicely formatted table
    }

data RepoLocationSpec = RepoLocal [FilePath] | RepoRemote String

-- | A datatype to represent the options what to list
data ListEntity = ListPackages
    | ListGroups
    | ListIndividuals [String]

pacReadOpts :: PackageReadOptions
pacReadOpts = defaultPackageReadOptions {
      _readOptStopOnDuplicates = False
    , _readOptIgnoreChecksums  = True
    , _readOptGenoCheck        = False
    , _readOptKeepMultipleVersions = True
    , _readOptIgnoreGeno = True
}

-- | The main function running the list command
runList :: ListOptions -> PoseidonIO ()
runList (ListOptions repoLocation listEntity rawOutput) = do
    (tableH, tableB) <- case listEntity of
        ListPackages -> do
            packageInfo <- case repoLocation of
                RepoRemote remoteURL -> do
                    logInfo "Downloading package data from server"
                    apiReturn <- processApiResponse (remoteURL ++ "/packages")
                    case apiReturn of
                        ApiReturnPackageInfo pacInfo -> return pacInfo
                        _ -> error "should not happen"
                RepoLocal baseDirs ->
                    map packageToPackageInfo <$> readPoseidonPackageCollection pacReadOpts baseDirs
            let tableH = ["Title", "Package Version", "Poseidon Version", "Description", "Last modified", "Nr Individuals"]
                tableB = sortOn head $ do
                    PackageInfo t v pv d l i <- packageInfo
                    return [t, showMaybe (showVersion <$> v), showVersion pv, showMaybe d, showMaybe (show <$> l), show i]
            return (tableH, tableB)
        ListGroups -> do
            groupInfo <- case repoLocation of
                RepoRemote remoteURL -> do
                    logInfo "Downloading group data from server"
                    apiReturn <- processApiResponse (remoteURL ++ "/groups")
                    case apiReturn of
                        ApiReturnGroupInfo groupInfo -> return groupInfo
                        _ -> error "should not happen"
                RepoLocal baseDirs -> getAllGroupInfo <$> readPoseidonPackageCollection pacReadOpts baseDirs
            let tableH = ["Group", "Packages", "Nr Individuals"]
                tableB = do
                    GroupInfo groupName pacsAndVersions nrInds <- groupInfo
                    let pacString = intercalate ", " [extendNameWithVersion pacName maybePacVersion | (pacName, maybePacVersion) <- pacsAndVersions]
                    return [groupName, pacString, show nrInds]
            return (tableH, tableB)
        ListIndividuals moreJannoColumns -> do
            (indInfo, pacVersions, additionalColumns) <- case repoLocation of
                RepoRemote remoteURL -> do
                    logInfo "Downloading individual data from server"
                    apiReturn <- processApiResponse (remoteURL ++ "/individuals?additionalJannoColumns=" ++ intercalate "," moreJannoColumns)
                    case apiReturn of
                        ApiReturnIndividualInfo i p c -> return (i, p, c)
                        _ -> error "should not happen"
                RepoLocal baseDirs -> do
                    allPackages <- readPoseidonPackageCollection pacReadOpts baseDirs
                    return $ getExtendedIndividualInfo allPackages moreJannoColumns

            -- warning in case the additional Columns do not exist in the entire janno dataset
            case additionalColumns of
                Just entriesAllInds -> forM_ (zip [0..] moreJannoColumns) $ \(i, columnKey) -> do
                    -- check entries in all individuals for that key
                    let nonEmptyEntries = catMaybes [entriesForInd !! i | entriesForInd <- entriesAllInds]
                    when (null nonEmptyEntries) . logWarning $ "Column Name " ++ columnKey ++ " not present in any individual"
                _ -> return ()

            let tableH = ["Package", "Individual", "Group"] ++ moreJannoColumns
                tableB = case additionalColumns of
                    Nothing -> do
                        (IndividualInfo name groups pac, maybePacVersion) <- zip indInfo pacVersions
                        let pacString = extendNameWithVersion pac maybePacVersion
                        return [pacString, name, intercalate ", " groups]
                    Just c -> do
                        (IndividualInfo name groups pac, maybePacVersion, addColumns) <- zip3 indInfo pacVersions c
                        let pacString = extendNameWithVersion pac maybePacVersion
                        return $ [pacString, name, intercalate ", " groups] ++ map (fromMaybe "n/a") addColumns
            return (tableH, tableB)
    if rawOutput then
        liftIO $ putStrLn $ intercalate "\n" [intercalate "\t" row | row <- tableB]
    else do
        let colSpecs = replicate (length tableH) (column (expandUntil 60) def def def)
        liftIO $ putStrLn $ tableString colSpecs asciiRoundS (titlesH tableH) [rowsG tableB]
  where
    showMaybe :: Maybe String -> String
    showMaybe = maybe "n/a" id
