module Poseidon.GoldenTestsRunCommands (
    createStaticCheckSumFile, createDynamicCheckSumFile, staticCheckSumFile, dynamicCheckSumFile
    ) where

import           Poseidon.EntitiesList      (PoseidonEntity (..))
import           Poseidon.CLI.Fetch         (FetchOptions (..), runFetch)
import           Poseidon.CLI.List          (ListOptions (..), runList, 
                                             RepoLocationSpec (..), ListEntity (..))
import           Poseidon.Package           (getChecksum)

import           Control.Monad              (when, unless)
import           GHC.IO.Handle              (hDuplicateTo, hDuplicate, hClose)
import           System.Directory           (createDirectory, removeDirectoryRecursive, doesDirectoryExist, copyFile)
import           System.FilePath.Posix      ((</>))
import           System.IO                  (stdout, IOMode(WriteMode), withFile, openFile, stderr)

tempTestDir :: FilePath
tempTestDir = "/tmp/poseidonHSGoldenTestData"

staticTestDir :: FilePath
staticTestDir = "test/testDat/poseidonHSGoldenTestData"

staticCheckSumFile :: FilePath
staticCheckSumFile = "test/testDat/staticCheckSumFile.txt"

dynamicCheckSumFile :: FilePath
dynamicCheckSumFile = "/tmp/poseidon_trident_dynamicCheckSumFile.txt"

createStaticCheckSumFile :: FilePath -> IO ()
createStaticCheckSumFile poseidonHSDir = runCLICommands 
    True
    (poseidonHSDir </> staticTestDir) 
    (poseidonHSDir </> staticCheckSumFile )

createDynamicCheckSumFile :: IO ()
createDynamicCheckSumFile = runCLICommands False tempTestDir dynamicCheckSumFile 

runCLICommands :: Bool -> FilePath -> FilePath -> IO ()
runCLICommands interactive testDir checkFilePath = do
    -- create temp dir for test output
    tmpTestDirExists <- doesDirectoryExist testDir
    when tmpTestDirExists $ removeDirectoryRecursive testDir
    createDirectory testDir
    -- create/overwrite checksum file
    writeFile checkFilePath "Checksums for trident CLI output \n\ 
        \Automatically generated with: ... \n\
        \"
    -- create error sink
    devNull <- openFile "/dev/null" WriteMode
    stderr_old <- hDuplicate stderr
    unless interactive $ hDuplicateTo devNull stderr
    -- run CLI pipeline
    testPipelineFetch testDir checkFilePath
    testPipelineList  testDir checkFilePath
    -- close error sink
    hClose devNull
    unless interactive $ hDuplicateTo stderr_old stderr

testPipelineFetch :: FilePath -> FilePath -> IO ()
testPipelineFetch testDir checkFilePath = do
    let fetchOpts1 = FetchOptions { 
          _jaBaseDirs       = [testDir]
        , _entityList       = [Pac "2019_Nikitin_LBK"]
        , _entityFiles      = []
        , _remoteURL        = "https://c107-224.cloud.gwdg.de"
        , _upgrade          = True
        , _downloadAllPacs  = False 
        }
    runAndChecksumFiles checkFilePath testDir (runFetch fetchOpts1) [
          "2019_Nikitin_LBK" </> "POSEIDON.yml"
        , "2019_Nikitin_LBK" </> "Nikitin_LBK.janno"
        , "2019_Nikitin_LBK" </> "Nikitin_LBK.fam"
        ]

testPipelineList :: FilePath -> FilePath -> IO ()
testPipelineList testDir checkFilePath = do
    let listOpts1 = ListOptions {
          _loRepoLocation  = RepoLocal [testDir  </> "2019_Nikitin_LBK"]
        , _loListEntity    = ListPackages
        , _loRawOutput     = False
        , _optIgnoreGeno   = False
        }
    runAndChecksumStdOut checkFilePath testDir (runList listOpts1) "tridentList1"
    let listOpts2 = listOpts1 {
          _loListEntity    = ListGroups
        }
    runAndChecksumStdOut checkFilePath testDir (runList listOpts2) "tridentList2"
    let listOpts3 = listOpts1 {
          _loListEntity    = ListIndividuals ["Country", "Nr_autosomal_SNPs"]
        }
    runAndChecksumStdOut checkFilePath testDir (runList listOpts3) "tridentList3"
    let listOpts4 = listOpts3 {
          _loRawOutput     = True
        }
    runAndChecksumStdOut checkFilePath testDir (runList listOpts4) "tridentList4"

runAndChecksumFiles :: FilePath -> FilePath -> IO () -> [FilePath] -> IO ()
runAndChecksumFiles checkSumFilePath testDir action outFiles = do
    -- run action
    action
    -- append checksums to checksum file
    mapM_ (appendChecksum checkSumFilePath testDir) outFiles
    where
        appendChecksum :: FilePath -> FilePath -> FilePath -> IO ()
        appendChecksum checkSumFilePath_ testDir_ outFile = do
            checksum <- getChecksum $ testDir_ </> outFile
            appendFile checkSumFilePath_ $ "\n" ++ checksum ++ " " ++ outFile

runAndChecksumStdOut :: FilePath -> FilePath -> IO () -> String -> IO ()
runAndChecksumStdOut checkSumFilePath testDir action outFileName = do
    -- store stdout in a specific output file
    withFile (testDir </> outFileName) WriteMode $ \handle -> do
        -- backup stdout handle
        stdout_old <- hDuplicate stdout
        -- redirect stdout to file
        hDuplicateTo handle stdout
        -- run action
        action
        -- load backup again
        hDuplicateTo stdout_old stdout
    -- append checksum to checksumfile
    checksum <- getChecksum $ testDir </> outFileName
    appendFile checkSumFilePath $ "\n" ++ checksum ++ " " ++ outFileName 
