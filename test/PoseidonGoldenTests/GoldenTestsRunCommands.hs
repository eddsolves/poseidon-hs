{-# LANGUAGE OverloadedStrings #-}

module PoseidonGoldenTests.GoldenTestsRunCommands (
    createStaticCheckSumFile, createDynamicCheckSumFile, staticCheckSumFile, dynamicCheckSumFile
    ) where

import           Poseidon.CLI.Fetch       (FetchOptions (..), runFetch)
import           Poseidon.CLI.Forge       (ForgeOptions (..), runForge)
import           Poseidon.CLI.Genoconvert (GenoconvertOptions (..),
                                           runGenoconvert)
import           Poseidon.CLI.Init        (InitOptions (..), runInit)
import           Poseidon.CLI.List        (ListEntity (..), ListOptions (..),
                                           RepoLocationSpec (..), runList)
import           Poseidon.CLI.Serve       (ServeOptions (..), runServer)
import           Poseidon.CLI.Summarise   (SummariseOptions (..), runSummarise)
import           Poseidon.CLI.Survey      (SurveyOptions (..), runSurvey)
import           Poseidon.CLI.Update      (UpdateOptions (..), runUpdate)
import           Poseidon.CLI.Validate    (ValidateOptions (..), runValidate)
import           Poseidon.EntitiesList    (EntityInput (..),
                                           PoseidonEntity (..),
                                           readEntitiesFromString)
import           Poseidon.GenotypeData    (GenoDataSource (..),
                                           GenotypeDataSpec (..),
                                           GenotypeFormatSpec (..),
                                           SNPSetSpec (..))
import           Poseidon.SecondaryTypes  (ContributorSpec (..),
                                           VersionComponent (..))
import           Poseidon.Utils           (getChecksum, testLog)

import           Control.Concurrent       (forkIO, killThread, newEmptyMVar)
import           Control.Concurrent.MVar  (takeMVar)
import           Control.Monad            (unless, when)
import           Data.Either              (fromRight)
import qualified Data.Text                as T
import qualified Data.Text.IO             as T
import           GHC.IO.Handle            (hClose, hDuplicate, hDuplicateTo)
import           SequenceFormats.Plink    (PlinkPopNameMode (..))
import           System.Directory         (createDirectory, doesDirectoryExist,
                                           removeDirectoryRecursive)
import           System.FilePath.Posix    ((</>))
import           System.IO                (IOMode (WriteMode), hPutStrLn,
                                           openFile, stderr, stdout, withFile)
tempTestDir         :: FilePath
tempTestDir         = "/tmp/poseidonHSGoldenTestData"
staticTestDir       :: FilePath
staticTestDir       = "test/PoseidonGoldenTests/GoldenTestData"
staticCheckSumFile  :: FilePath
staticCheckSumFile  = "test/PoseidonGoldenTests/GoldenTestCheckSumFile.txt"
dynamicCheckSumFile :: FilePath
dynamicCheckSumFile = "/tmp/poseidon_trident_dynamicCheckSumFile.txt"
testPacsDir         :: FilePath
testPacsDir         = "test/testDat/testPackages/ancient"
testEntityFiles     :: FilePath
testEntityFiles     = "test/testDat/testEntityFiles"

createStaticCheckSumFile :: FilePath -> IO ()
createStaticCheckSumFile d = runCLICommands True (d </> staticTestDir) (d </> staticCheckSumFile)
createDynamicCheckSumFile :: IO ()
createDynamicCheckSumFile = runCLICommands False tempTestDir dynamicCheckSumFile

runCLICommands :: Bool -> FilePath -> FilePath -> IO ()
runCLICommands interactive testDir checkFilePath = do
    -- create temp dir for test output
    tmpTestDirExists <- doesDirectoryExist testDir
    when tmpTestDirExists $ removeDirectoryRecursive testDir
    createDirectory testDir
    -- create/overwrite checksum file
    writeFile checkFilePath "Checksums for trident CLI output\n\
        \Automatically generated with: poseidon-devtools golden\n"
    -- create error sink
    devNull <- openFile "/dev/null" WriteMode
    stderr_old <- hDuplicate stderr
    unless interactive $ hDuplicateTo devNull stderr
    -- run CLI pipeline
    hPutStrLn stderr "--* local tests"
    hPutStrLn stderr "--- init"
    testPipelineInit testDir checkFilePath
    hPutStrLn stderr "--- validate"
    testPipelineValidate testDir checkFilePath
    hPutStrLn stderr "--- list"
    testPipelineList testDir checkFilePath
    hPutStrLn stderr "--- summarise"
    testPipelineSummarise testDir checkFilePath
    hPutStrLn stderr "--- survey"
    testPipelineSurvey testDir checkFilePath
    hPutStrLn stderr "--- genoconvert"
    testPipelineGenoconvert testDir checkFilePath
    hPutStrLn stderr "--- update"
    testPipelineUpdate testDir checkFilePath
    hPutStrLn stderr "--- forge"
    testPipelineForge testDir checkFilePath
    hPutStrLn stderr "--* test server interaction"
    hPutStrLn stderr "--- fetch"
    testPipelineFetch testDir checkFilePath
    hPutStrLn stderr "--- list --remote"
    testPipelineListRemote testDir checkFilePath
    -- close error sink
    hClose devNull
    unless interactive $ hDuplicateTo stderr_old stderr

testPipelineInit :: FilePath -> FilePath -> IO ()
testPipelineInit testDir checkFilePath = do
    let initOpts1 = InitOptions {
          _initGenoData  = GenotypeDataSpec {
              format   = GenotypeFormatEigenstrat
            , genoFile = testPacsDir </> "Schiffels_2016" </> "geno.txt"
            , genoFileChkSum = Nothing
            , snpFile  = testPacsDir </> "Schiffels_2016" </> "snp.txt"
            , snpFileChkSum = Nothing
            , indFile  = testPacsDir </> "Schiffels_2016" </> "ind.txt"
            , indFileChkSum = Nothing
            , snpSet   = Just SNPSetOther
            }
        , _initPacPath      = testDir </> "init" </> "Schiffels"
        , _initPacName      = Just "Schiffels"
        , _initMinimal      = False
    }
    let action = testLog (runInit initOpts1) >>
                 patchLastModified testDir ("init" </> "Schiffels" </> "POSEIDON.yml")
    runAndChecksumFiles checkFilePath testDir action "init" [
          "init" </> "Schiffels" </> "POSEIDON.yml"
        , "init" </> "Schiffels" </> "Schiffels.janno"
        , "init" </> "Schiffels" </> "geno.txt"
        , "init" </> "Schiffels" </> "Schiffels.bib"
        ]
    let initOpts2 = InitOptions {
          _initGenoData  = GenotypeDataSpec {
            format   = GenotypeFormatPlink
          , genoFile = testPacsDir </> "Wang_2020" </> "Wang_2020.bed"
          , genoFileChkSum = Nothing
          , snpFile  = testPacsDir </> "Wang_2020" </> "Wang_2020.bim"
          , snpFileChkSum = Nothing
          , indFile  = testPacsDir </> "Wang_2020" </> "Wang_2020.fam"
          , indFileChkSum = Nothing
          , snpSet   = Just SNPSetOther
          }
        , _initPacPath   = testDir </> "init" </> "Wang"
        , _initPacName   = Nothing
        , _initMinimal   = True
    }
    let action2 = testLog (runInit initOpts2) >>
                  patchLastModified testDir ("init" </> "Wang" </> "POSEIDON.yml")
    runAndChecksumFiles checkFilePath testDir action2 "init" [
          "init" </> "Wang" </> "POSEIDON.yml"
        , "init" </> "Wang" </> "Wang_2020.bed"
        ]

testPipelineValidate :: FilePath -> FilePath -> IO ()
testPipelineValidate testDir checkFilePath = do
    let validateOpts1 = ValidateOptions {
          _validateBaseDirs     = [testPacsDir]
        , _validateIgnoreGeno   = False
        , _validateFullGeno     = False
        , _validateNoExitCode   = True
        , _validateIgnoreDuplicates = True
    }
    runAndChecksumStdOut checkFilePath testDir (testLog $ runValidate validateOpts1) "validate" 1
    let validateOpts2 = validateOpts1 {
          _validateIgnoreGeno   = True
    }
    runAndChecksumStdOut checkFilePath testDir (testLog $ runValidate validateOpts2) "validate" 2
    let validateOpts3 = validateOpts1 {
          _validateFullGeno     = True
    }
    runAndChecksumStdOut checkFilePath testDir (testLog $ runValidate validateOpts3) "validate" 3
    -- validate packages generated with init
    let validateOpts4 = validateOpts1 {
          _validateBaseDirs     = [testDir </> "init"]
    }
    runAndChecksumStdOut checkFilePath testDir (testLog $ runValidate validateOpts4) "validate" 4

testPipelineList :: FilePath -> FilePath -> IO ()
testPipelineList testDir checkFilePath = do
    let listOpts1 = ListOptions {
          _listRepoLocation  = RepoLocal [testPacsDir </> "Schiffels_2016", testPacsDir  </> "Wang_Wang_2020"]
        , _listListEntity    = ListPackages
        , _listRawOutput     = False
        }
    runAndChecksumStdOut checkFilePath testDir (testLog $ runList listOpts1) "list" 1
    let listOpts2 = listOpts1 {
          _listListEntity    = ListGroups
        }
    runAndChecksumStdOut checkFilePath testDir (testLog $ runList listOpts2) "list" 2
    let listOpts3 = listOpts1 {
          _listListEntity    = ListIndividuals ["Country", "Nr_SNPs"]
        }
    runAndChecksumStdOut checkFilePath testDir (testLog $ runList listOpts3) "list" 3
    let listOpts4 = listOpts3 {
          _listRawOutput     = True
        }
    runAndChecksumStdOut checkFilePath testDir (testLog $ runList listOpts4) "list" 4

testPipelineSummarise :: FilePath -> FilePath -> IO ()
testPipelineSummarise testDir checkFilePath = do
    let summariseOpts1 = SummariseOptions {
          _summariseBaseDirs = [testPacsDir]
        , _summariseRawOutput = False
    }
    runAndChecksumStdOut checkFilePath testDir (testLog $ runSummarise summariseOpts1) "summarise" 1
    let summariseOpts2 = SummariseOptions {
          _summariseBaseDirs = [testPacsDir]
        , _summariseRawOutput = True
    }
    runAndChecksumStdOut checkFilePath testDir (testLog $ runSummarise summariseOpts2) "summarise" 2

testPipelineSurvey :: FilePath -> FilePath -> IO ()
testPipelineSurvey testDir checkFilePath = do
    let surveyOpts1 = SurveyOptions {
          _surveyBaseDirs = [testPacsDir]
        , _surveyRawOutput = False
    }
    runAndChecksumStdOut checkFilePath testDir (testLog $ runSurvey surveyOpts1) "survey" 1
    let surveyOpts2 = SurveyOptions {
          _surveyBaseDirs = [testPacsDir]
        , _surveyRawOutput = True
    }
    runAndChecksumStdOut checkFilePath testDir (testLog $ runSurvey surveyOpts2) "survey" 2

testPipelineGenoconvert :: FilePath -> FilePath -> IO ()
testPipelineGenoconvert testDir checkFilePath = do
    let genoconvertOpts1 = GenoconvertOptions {
          _genoconvertGenoSources = [PacBaseDir $ testPacsDir </> "Schiffels_2016"]
        , _genoConvertOutFormat = GenotypeFormatPlink
        , _genoConvertOutOnlyGeno = False
        , _genoMaybeOutPackagePath = Just $ testDir </> "genoconvert" </> "Schiffels"
        , _genoconvertRemoveOld = False
        , _genoconvertOutPlinkPopMode = PlinkPopNameAsFamily
    }
    runAndChecksumFiles checkFilePath testDir (testLog $ runGenoconvert genoconvertOpts1) "genoconvert" [
          "genoconvert" </> "Schiffels" </> "Schiffels_2016.bed"
        , "genoconvert" </> "Schiffels" </> "Schiffels_2016.bim"
        , "genoconvert" </> "Schiffels" </> "Schiffels_2016.fam"
        ]
    let genoconvertOpts2 = GenoconvertOptions {
          _genoconvertGenoSources = [PacBaseDir $ testPacsDir </> "Schiffels_2016"]
        , _genoConvertOutFormat = GenotypeFormatPlink
        , _genoConvertOutOnlyGeno = False
        , _genoMaybeOutPackagePath = Just $ testDir </> "genoconvert" </> "Schiffels_otherPlinkEncoding"
        , _genoconvertRemoveOld = False
        , _genoconvertOutPlinkPopMode = PlinkPopNameAsPhenotype
    }
    runAndChecksumFiles checkFilePath testDir (testLog $ runGenoconvert genoconvertOpts2) "genoconvert" [
          "genoconvert" </> "Schiffels_otherPlinkEncoding" </> "Schiffels_2016.bed"
        , "genoconvert" </> "Schiffels_otherPlinkEncoding" </> "Schiffels_2016.bim"
        , "genoconvert" </> "Schiffels_otherPlinkEncoding" </> "Schiffels_2016.fam"
        ]
    -- in-place conversion
    let genoconvertOpts3 = GenoconvertOptions {
          _genoconvertGenoSources = [PacBaseDir $ testDir </> "init" </> "Wang"]
        , _genoConvertOutFormat = GenotypeFormatEigenstrat
        , _genoConvertOutOnlyGeno = False
        , _genoMaybeOutPackagePath = Nothing
        , _genoconvertRemoveOld = False
        , _genoconvertOutPlinkPopMode = PlinkPopNameAsFamily
    }
    runAndChecksumFiles checkFilePath testDir (testLog $ runGenoconvert genoconvertOpts3) "genoconvert" [
          "init" </> "Wang" </> "Wang.geno"
        , "init" </> "Wang" </> "Wang.snp"
        , "init" </> "Wang" </> "Wang.ind"
        ]
    let genoconvertOpts4 = GenoconvertOptions {
          _genoconvertGenoSources = [
            GenoDirect $
              GenotypeDataSpec {
                  format   = GenotypeFormatEigenstrat
                , genoFile = testDir </> "init" </> "Schiffels" </> "geno.txt"
                , genoFileChkSum = Nothing
                , snpFile  = testDir </> "init" </> "Schiffels" </> "snp.txt"
                , snpFileChkSum = Nothing
                , indFile  = testDir </> "init" </> "Schiffels" </> "ind.txt"
                , indFileChkSum = Nothing
                , snpSet   = Just SNPSetOther
              }
          ]
        , _genoConvertOutFormat = GenotypeFormatPlink
        , _genoConvertOutOnlyGeno = True
        , _genoMaybeOutPackagePath = Nothing
        , _genoconvertRemoveOld = False
        , _genoconvertOutPlinkPopMode = PlinkPopNameAsFamily
    }
    runAndChecksumFiles checkFilePath testDir (testLog $ runGenoconvert genoconvertOpts4) "genoconvert" [
          "init" </> "Schiffels" </> "geno.bed"
        , "init" </> "Schiffels" </> "geno.bim"
        , "init" </> "Schiffels" </> "geno.fam"
        ]

testPipelineUpdate :: FilePath -> FilePath -> IO ()
testPipelineUpdate testDir checkFilePath = do
    -- in-place conversion
    let updateOpts1 = UpdateOptions {
          _updateBaseDirs = [testDir </> "init" </> "Schiffels"]
        , _updatePoseidonVersion = Nothing
        , _updateIgnorePoseidonVersion = False
        , _updateVersionUpdate = Major
        , _updateNoChecksumUpdate = True
        , _updateIgnoreGeno = True
        , _updateNewContributors = []
        , _updateLog = "test1"
        , _updateForce = True
        }
    let action1 = testLog (runUpdate updateOpts1) >> patchLastModified testDir ("init" </> "Schiffels" </> "POSEIDON.yml")
    runAndChecksumFiles checkFilePath testDir action1 "update" [
          "init" </> "Schiffels" </> "POSEIDON.yml"
        , "init" </> "Schiffels" </> "CHANGELOG.md"
        ]
    let updateOpts2 = UpdateOptions {
          _updateBaseDirs = [testDir </> "Schiffels"]
        , _updatePoseidonVersion = Nothing
        , _updateIgnorePoseidonVersion = False
        , _updateVersionUpdate = Minor
        , _updateNoChecksumUpdate = False
        , _updateIgnoreGeno = False
        , _updateNewContributors = []
        , _updateLog = "test2"
        , _updateForce = False
        }
    let action2 = testLog (runUpdate updateOpts2) >> patchLastModified testDir ("init" </> "Schiffels" </> "POSEIDON.yml")
    runAndChecksumFiles checkFilePath testDir action2 "update" [
          "init" </> "Schiffels" </> "POSEIDON.yml"
        , "init" </> "Schiffels" </> "CHANGELOG.md"
        ]
    let updateOpts3 = UpdateOptions {
          _updateBaseDirs = [testDir </> "Schiffels"]
        , _updatePoseidonVersion = Nothing
        , _updateIgnorePoseidonVersion = False
        , _updateVersionUpdate = Patch
        , _updateNoChecksumUpdate = False
        , _updateIgnoreGeno = False
        , _updateNewContributors = [
            ContributorSpec "Berta Testfrau" "berta@testfrau.org" Nothing,
            ContributorSpec "Herbert Testmann" "herbert@testmann.tw" Nothing
            ]
        , _updateLog = "test3"
        , _updateForce = True
        }
    let action3 = testLog (runUpdate updateOpts3) >> patchLastModified testDir ("init" </> "Schiffels" </> "POSEIDON.yml")
    runAndChecksumFiles checkFilePath testDir action3 "update" [
          "init" </> "Schiffels" </> "POSEIDON.yml"
        , "init" </> "Schiffels" </> "CHANGELOG.md"
        ]

testPipelineForge :: FilePath -> FilePath -> IO ()
testPipelineForge testDir checkFilePath = do
    -- forge test 1
    let forgeOpts1 = ForgeOptions {
          _forgeGenoSources  = [PacBaseDir $ testPacsDir </> "Schiffels_2016", PacBaseDir $ testPacsDir </> "Wang_2020"]
        , _forgeEntityInput  = [EntitiesDirect (fromRight [] $ readEntitiesFromString "POP2,<SAMPLE2>,<SAMPLE4>")]
        , _forgeSnpFile      = Nothing
        , _forgeIntersect    = False
        , _forgeOutFormat    = GenotypeFormatEigenstrat
        , _forgeOutMinimal   = False
        , _forgeOutOnlyGeno  = False
        , _forgeOutPacPath   = testDir </> "forge" </> "ForgePac1"
        , _forgeOutPacName   = Just "ForgePac1"
        , _forgePackageWise    = False
        , _forgeOutputPlinkPopMode = PlinkPopNameAsFamily
    }
    let action1 = testLog (runForge forgeOpts1) >> patchLastModified testDir ("forge" </> "ForgePac1" </> "POSEIDON.yml")
    runAndChecksumFiles checkFilePath testDir action1 "forge" [
          "forge" </> "ForgePac1" </> "POSEIDON.yml"
        , "forge" </> "ForgePac1" </> "ForgePac1.geno"
        , "forge" </> "ForgePac1" </> "ForgePac1.janno"
        , "forge" </> "ForgePac1" </> "ForgePac1.ssf"
        , "forge" </> "ForgePac1" </> "ForgePac1.bib"
        ]
    -- forge test 2
    let forgeOpts2 = ForgeOptions {
          _forgeGenoSources  = [PacBaseDir $ testPacsDir </> "Schiffels_2016", PacBaseDir $ testPacsDir </> "Wang_2020"]
        , _forgeEntityInput  = [EntitiesDirect (fromRight [] $ readEntitiesFromString "POP2,<SAMPLE2>,<SAMPLE4>,-<SAMPLE3>")]
        , _forgeSnpFile      = Nothing
        , _forgeIntersect    = False
        , _forgeOutFormat    = GenotypeFormatPlink
        , _forgeOutMinimal   = True
        , _forgeOutOnlyGeno  = False
        , _forgeOutPacPath   = testDir </> "forge" </> "ForgePac2"
        , _forgeOutPacName   = Nothing
        , _forgePackageWise    = False
        , _forgeOutputPlinkPopMode = PlinkPopNameAsFamily
    }
    let action2 = testLog (runForge forgeOpts2) >> patchLastModified testDir ("forge" </> "ForgePac2" </> "POSEIDON.yml")
    runAndChecksumFiles checkFilePath testDir action2 "forge" [
          "forge" </> "ForgePac2" </> "POSEIDON.yml"
        , "forge" </> "ForgePac2" </> "ForgePac2.bed"
        ]
    -- forge test 3
    let forgeOpts3 = ForgeOptions {
          _forgeGenoSources  = [PacBaseDir $ testPacsDir </> "Schiffels_2016", PacBaseDir $ testPacsDir </> "Wang_2020"]
        , _forgeEntityInput  = [EntitiesFromFile (testEntityFiles </> "goldenTestForgeFile1.txt")]
        , _forgeSnpFile      = Nothing
        , _forgeIntersect    = False
        , _forgeOutFormat    = GenotypeFormatEigenstrat
        , _forgeOutMinimal   = False
        , _forgeOutOnlyGeno  = False
        , _forgeOutPacPath   = testDir </> "forge" </> "ForgePac3"
        , _forgeOutPacName   = Nothing
        , _forgePackageWise    = False
        , _forgeOutputPlinkPopMode = PlinkPopNameAsFamily
    }
    let action3 = testLog (runForge forgeOpts3) >> patchLastModified testDir ("forge" </> "ForgePac3" </> "POSEIDON.yml")
    runAndChecksumFiles checkFilePath testDir action3 "forge" [
          "forge" </> "ForgePac3" </> "POSEIDON.yml"
        , "forge" </> "ForgePac3" </> "ForgePac3.geno"
        , "forge" </> "ForgePac3" </> "ForgePac3.snp"
        , "forge" </> "ForgePac3" </> "ForgePac3.ind"
        , "forge" </> "ForgePac3" </> "ForgePac3.janno"
        , "forge" </> "ForgePac3" </> "ForgePac3.ssf"
        ]
    -- forge test 4
    let forgeOpts4 = ForgeOptions {
          _forgeGenoSources  = [PacBaseDir $ testPacsDir </> "Schiffels_2016", PacBaseDir $ testPacsDir </> "Wang_2020"]
        , _forgeEntityInput  = [EntitiesFromFile (testEntityFiles </> "goldenTestForgeFile2.txt")]
        , _forgeSnpFile      = Nothing
        , _forgeIntersect    = False
        , _forgeOutFormat    = GenotypeFormatPlink
        , _forgeOutMinimal   = False
        , _forgeOutOnlyGeno  = False
        , _forgeOutPacPath   = testDir </> "forge" </> "ForgePac4"
        , _forgeOutPacName   = Nothing
        , _forgePackageWise    = False
        , _forgeOutputPlinkPopMode = PlinkPopNameAsFamily
    }
    let action4 = testLog (runForge forgeOpts4) >> patchLastModified testDir ("forge" </> "ForgePac4" </> "POSEIDON.yml")
    runAndChecksumFiles checkFilePath testDir action4 "forge" [
          "forge" </> "ForgePac4" </> "POSEIDON.yml"
        , "forge" </> "ForgePac4" </> "ForgePac4.bim"
        , "forge" </> "ForgePac4" </> "ForgePac4.bed"
        , "forge" </> "ForgePac4" </> "ForgePac4.fam"
        , "forge" </> "ForgePac4" </> "ForgePac4.janno"
        , "forge" </> "ForgePac4" </> "ForgePac4.ssf"
        ]
    -- forge test 5
    let forgeOpts5 = ForgeOptions {
          _forgeGenoSources  = [PacBaseDir $ testPacsDir </> "Schiffels_2016", PacBaseDir $ testPacsDir </> "Wang_2020"]
        , _forgeEntityInput  = []
        , _forgeIntersect    = False
        , _forgeOutFormat    = GenotypeFormatEigenstrat
        , _forgeOutMinimal   = False
        , _forgeOutOnlyGeno  = False
        , _forgeOutPacPath   = testDir </> "forge" </> "ForgePac5"
        , _forgeOutPacName   = Just "ForgePac5"
        , _forgePackageWise  = False
        , _forgeSnpFile      = Nothing
        , _forgeOutputPlinkPopMode = PlinkPopNameAsFamily
    }
    let action5 = testLog (runForge forgeOpts5) >> patchLastModified testDir ("forge" </> "ForgePac5" </> "POSEIDON.yml")
    runAndChecksumFiles checkFilePath testDir action5 "forge" [
          "forge" </> "ForgePac5" </> "POSEIDON.yml"
        , "forge" </> "ForgePac5" </> "ForgePac5.geno"
        , "forge" </> "ForgePac5" </> "ForgePac5.janno"
        , "forge" </> "ForgePac5" </> "ForgePac5.ssf"
        ]
    -- forge test 6 (direct genotype data input interface)
    let forgeOpts6 = ForgeOptions {
          _forgeGenoSources = [
            GenoDirect $
              GenotypeDataSpec {
                  format   = GenotypeFormatEigenstrat
                , genoFile = testPacsDir </> "Schiffels_2016" </> "geno.txt"
                , genoFileChkSum = Nothing
                , snpFile  = testPacsDir </> "Schiffels_2016" </> "snp.txt"
                , snpFileChkSum = Nothing
                , indFile  = testPacsDir </> "Schiffels_2016" </> "ind.txt"
                , indFileChkSum = Nothing
                , snpSet   = Just SNPSetOther
              },
            GenoDirect $
              GenotypeDataSpec {
                  format   = GenotypeFormatPlink
                , genoFile = testPacsDir </> "Wang_2020" </> "Wang_2020.bed"
                , genoFileChkSum = Nothing
                , snpFile  = testPacsDir </> "Wang_2020" </> "Wang_2020.bim"
                , snpFileChkSum = Nothing
                , indFile  = testPacsDir </> "Wang_2020" </> "Wang_2020.fam"
                , indFileChkSum = Nothing
                , snpSet   = Just SNPSetOther
              }
          ]
        , _forgeEntityInput  = [EntitiesDirect (fromRight [] $ readEntitiesFromString "POP2,<SAMPLE2>,<SAMPLE4>")]
        , _forgeIntersect    = False
        , _forgeOutFormat    = GenotypeFormatEigenstrat
        , _forgeOutMinimal   = False
        , _forgeOutOnlyGeno  = True
        , _forgeOutPacPath   = testDir </> "forge" </> "ForgePac6"
        , _forgeOutPacName   = Just "ForgePac6"
        , _forgePackageWise  = False
        , _forgeSnpFile      = Nothing
        , _forgeOutputPlinkPopMode = PlinkPopNameAsFamily
    }
    let action6 = testLog (runForge forgeOpts6)
    runAndChecksumFiles checkFilePath testDir action6 "forge" [
          "forge" </> "ForgePac6" </> "ForgePac6.geno"
        , "forge" </> "ForgePac6" </> "ForgePac6.snp"
        , "forge" </> "ForgePac6" </> "ForgePac6.ind"
        ]
    -- forge test 7 (mixed data input interface)
    let forgeOpts7 = ForgeOptions {
          _forgeGenoSources  = [
            PacBaseDir $ testPacsDir </> "Schiffels_2016",
            GenoDirect $
              GenotypeDataSpec {
                  format   = GenotypeFormatPlink
                , genoFile = testPacsDir </> "Wang_2020" </> "Wang_2020.bed"
                , genoFileChkSum = Nothing
                , snpFile  = testPacsDir </> "Wang_2020" </> "Wang_2020.bim"
                , snpFileChkSum = Nothing
                , indFile  = testPacsDir </> "Wang_2020" </> "Wang_2020.fam"
                , indFileChkSum = Nothing
                , snpSet   = Just SNPSetOther
              }
            ]
        , _forgeEntityInput  = [EntitiesDirect (fromRight [] $ readEntitiesFromString "POP2,<SAMPLE2>,<SAMPLE4>")]
        , _forgeIntersect    = False
        , _forgeOutFormat    = GenotypeFormatEigenstrat
        , _forgeOutMinimal   = False
        , _forgeOutOnlyGeno  = False
        , _forgeOutPacPath   = testDir </> "forge" </> "ForgePac7"
        , _forgeOutPacName   = Just "ForgePac7"
        , _forgePackageWise  = False
        , _forgeSnpFile      = Nothing
        , _forgeOutputPlinkPopMode = PlinkPopNameAsFamily
    }
    let action7 = testLog (runForge forgeOpts7) >> patchLastModified testDir ("forge" </> "ForgePac7" </> "POSEIDON.yml")
    runAndChecksumFiles checkFilePath testDir action7 "forge" [
          "forge" </> "ForgePac7" </> "ForgePac7.geno"
        , "forge" </> "ForgePac7" </> "ForgePac7.snp"
        , "forge" </> "ForgePac7" </> "ForgePac7.ind"
        , "forge" </> "ForgePac7" </> "ForgePac7.janno"
        ]
    -- forge test 8 (combining additional janno columns from separate source janno files)
    let forgeOpts8 = ForgeOptions {
          _forgeGenoSources  = [PacBaseDir $ testPacsDir </> "Schiffels_2016", PacBaseDir $ testPacsDir </> "Lamnidis_2018_newVersion"]
        , _forgeEntityInput  = [EntitiesDirect (fromRight [] $ readEntitiesFromString "<XXX001>,<XXX011>")]
        , _forgeSnpFile      = Nothing
        , _forgeIntersect    = False
        , _forgeOutFormat    = GenotypeFormatEigenstrat
        , _forgeOutMinimal   = False
        , _forgeOutOnlyGeno  = False
        , _forgeOutPacPath   = testDir </> "forge" </> "ForgePac8"
        , _forgeOutPacName   = Just "ForgePac8"
        , _forgePackageWise    = False
        , _forgeOutputPlinkPopMode = PlinkPopNameAsFamily
    }
    let action8 = testLog (runForge forgeOpts8) >> patchLastModified testDir ("forge" </> "ForgePac8" </> "POSEIDON.yml")
    runAndChecksumFiles checkFilePath testDir action8 "forge" [
          "forge" </> "ForgePac8" </> "ForgePac8.janno"
        , "forge" </> "ForgePac8" </> "ForgePac8.ssf"
        ]
    -- forge test 9 (duplicates are handled correctly if an individual is properly specified)
    let forgeOpts9 = ForgeOptions {
          _forgeGenoSources  = [PacBaseDir $ testPacsDir </> "Schiffels_2016", PacBaseDir $ testPacsDir </> "Schmid_2028"]
        , _forgeEntityInput  = [EntitiesDirect (fromRight [] $ readEntitiesFromString "POP1,<Schmid_2028:POP1:XXX001>")]
        , _forgeSnpFile      = Nothing
        , _forgeIntersect    = False
        , _forgeOutFormat    = GenotypeFormatEigenstrat
        , _forgeOutMinimal   = False
        , _forgeOutOnlyGeno  = False
        , _forgeOutPacPath   = testDir </> "forge" </> "ForgePac9"
        , _forgeOutPacName   = Just "ForgePac9"
        , _forgePackageWise    = False
        , _forgeOutputPlinkPopMode = PlinkPopNameAsFamily
    }
    let action9 = testLog (runForge forgeOpts9) >> patchLastModified testDir ("forge" </> "ForgePac9" </> "POSEIDON.yml")
    runAndChecksumFiles checkFilePath testDir action9 "forge" [
          "forge" </> "ForgePac9" </> "ForgePac9.geno"
        , "forge" </> "ForgePac9" </> "ForgePac9.janno"
        , "forge" </> "ForgePac9" </> "ForgePac9.ssf"
        ]
    -- forge test 10 (duplicates can also be resolved with negative selection)
    let forgeOpts10 = ForgeOptions {
          _forgeGenoSources  = [PacBaseDir $ testPacsDir </> "Schiffels_2016", PacBaseDir $ testPacsDir </> "Schmid_2028"]
        , _forgeEntityInput  = [EntitiesDirect (fromRight [] $ readEntitiesFromString "-<Schmid_2028:POP1:XXX001>,-<Schiffels_2016:POP2:XXX002>")]
        , _forgeSnpFile      = Nothing
        , _forgeIntersect    = False
        , _forgeOutFormat    = GenotypeFormatEigenstrat
        , _forgeOutMinimal   = False
        , _forgeOutOnlyGeno  = False
        , _forgeOutPacPath   = testDir </> "forge" </> "ForgePac10"
        , _forgeOutPacName   = Just "ForgePac10"
        , _forgePackageWise    = False
        , _forgeOutputPlinkPopMode = PlinkPopNameAsFamily
    }
    let action10 = testLog (runForge forgeOpts10) >> patchLastModified testDir ("forge" </> "ForgePac10" </> "POSEIDON.yml")
    runAndChecksumFiles checkFilePath testDir action10 "forge" [
          "forge" </> "ForgePac10" </> "ForgePac10.geno"
        , "forge" </> "ForgePac10" </> "ForgePac10.janno"
        , "forge" </> "ForgePac10" </> "ForgePac10.ssf"
        , "forge" </> "ForgePac10" </> "ForgePac10.bib"
        ]
    -- forge test 11 (--packagewise works as expected)
    let forgeOpts11 = ForgeOptions {
          _forgeGenoSources  = [PacBaseDir $ testPacsDir </> "Schiffels_2016", PacBaseDir $ testPacsDir </> "Schmid_2028"]
        , _forgeEntityInput  = [EntitiesDirect (fromRight [] $ readEntitiesFromString "POP3")]
        , _forgeSnpFile      = Nothing
        , _forgeIntersect    = False
        , _forgeOutFormat    = GenotypeFormatEigenstrat
        , _forgeOutMinimal   = False
        , _forgeOutOnlyGeno  = False
        , _forgeOutPacPath   = testDir </> "forge" </> "ForgePac11"
        , _forgeOutPacName   = Just "ForgePac11"
        , _forgePackageWise  = True
        , _forgeOutputPlinkPopMode = PlinkPopNameAsFamily
    }
    let action11 = testLog (runForge forgeOpts11) >> patchLastModified testDir ("forge" </> "ForgePac11" </> "POSEIDON.yml")
    runAndChecksumFiles checkFilePath testDir action11 "forge" [
          "forge" </> "ForgePac11" </> "ForgePac11.geno"
        , "forge" </> "ForgePac11" </> "ForgePac11.janno"
        , "forge" </> "ForgePac11" </> "ForgePac11.ssf"
        ]

 -- Note: We here use our test server (no SSL and different port). The reason is that
 -- sometimes we would like to implement new features that affect the communication
 -- between server and client, and we need tests succeeding before Pull Requests are merged, so
 -- we adopt the policy to run experimental builds on the test server in order to test features
 -- before running them on the main server.
testPipelineFetch :: FilePath -> FilePath -> IO ()
testPipelineFetch testDir checkFilePath = do

    let serverOpts = ServeOptions ["test/testDat/testPackages"] (Just "/tmp/zip_dir") 3000 True Nothing

    -- we prepare an empty MVar, which is filled as soon as the server is ready
    serverReady <- newEmptyMVar

    -- this will start the server on another thread
    threadID <- forkIO (testLog $ runServer serverOpts serverReady)

    -- takeMVar will block the main thread until the server is ready
    _ <- takeMVar serverReady

    let fetchOpts1 = FetchOptions {
          _jaBaseDirs   = [testDir </> "fetch"]
        , _entityInput  = [EntitiesDirect [Pac "Schmid_2028"]]
        , _remoteURL    = "http://localhost:3000"
        }
    runAndChecksumFiles checkFilePath testDir (testLog $ runFetch fetchOpts1) "fetch" [
          "fetch" </> "Schmid_2028-1.0.0" </> "POSEIDON.yml"
        , "fetch" </> "Schmid_2028-1.0.0" </> "Schmid_2028.janno"
        , "fetch" </> "Schmid_2028-1.0.0" </> "geno.txt"
        ]

    -- kill server thread
    killThread threadID

testPipelineListRemote :: FilePath -> FilePath -> IO ()
testPipelineListRemote testDir checkFilePath = do
    let serverOpts = ServeOptions ["test/testDat/testPackages"] Nothing 3000 True Nothing

    -- see above
    serverReady <- newEmptyMVar
    threadID <- forkIO (testLog $ runServer serverOpts serverReady)
    _ <- takeMVar serverReady

    let listOpts1 = ListOptions {
          _listRepoLocation = RepoRemote "http://localhost:3000"
        , _listListEntity   = ListPackages
        , _listRawOutput    = False
        }
    runAndChecksumStdOut checkFilePath testDir (testLog $ runList listOpts1) "listRemote" 1
    let listOpts2 = listOpts1 {
          _listListEntity    = ListGroups
        }
    runAndChecksumStdOut checkFilePath testDir (testLog $ runList listOpts2) "listRemote" 2
    let listOpts3 = listOpts1 {
          _listListEntity    = ListIndividuals ["Publication"]
        , _listRawOutput     = True
        }
    runAndChecksumStdOut checkFilePath testDir (testLog $ runList listOpts3) "listRemote" 3

    killThread threadID

-- helper functions --

patchLastModified :: FilePath -> FilePath -> IO ()
patchLastModified testDir yamlFile = do
    lines_ <- T.lines <$> T.readFile (testDir </> yamlFile)
    let patchedLines = do
            l <- lines_
            if "lastModified" `T.isPrefixOf` l
                then return "lastModified: 1970-01-01"
                else return l
    T.writeFile (testDir </> yamlFile) (T.unlines patchedLines)

runAndChecksumFiles :: FilePath -> FilePath -> IO () -> String -> [FilePath] -> IO ()
runAndChecksumFiles checkSumFilePath testDir action actionName outFiles = do
    -- run action
    action
    -- append checksums to checksum file
    mapM_ (appendChecksum checkSumFilePath testDir actionName) outFiles
    where
        appendChecksum :: FilePath -> FilePath -> FilePath -> String -> IO ()
        appendChecksum checkSumFilePath_ testDir_ actionName_ outFile = do
            checksum <- getChecksum $ testDir_ </> outFile
            appendFile checkSumFilePath_ $ "\n" ++ checksum ++ " " ++ actionName_ ++ " " ++ outFile

runAndChecksumStdOut :: FilePath -> FilePath -> IO () -> String -> Integer -> IO ()
runAndChecksumStdOut checkSumFilePath testDir action actionName outFileNumber = do
    -- store stdout in a specific output file
    let outFileName = actionName ++ show outFileNumber
        outDirInTestDir = actionName </> outFileName
        outDir = testDir </> actionName
        outPath = outDir </> outFileName
    -- create outdir if it doesn't exist
    outDirExists <- doesDirectoryExist outDir
    unless outDirExists $ createDirectory outDir
    -- catch stdout and write it to the outPath
    writeStdOutToFile outPath action
    -- append checksum to checksumfile
    checksum <- getChecksum $ outPath
    appendFile checkSumFilePath $ "\n" ++ checksum ++ " " ++ actionName ++ " " ++ outDirInTestDir

writeStdOutToFile :: FilePath -> IO () -> IO ()
writeStdOutToFile path action =
    withFile path WriteMode $ \handle -> do
      -- backup stdout handle
      stdout_old <- hDuplicate stdout
      -- redirect stdout to file
      hDuplicateTo handle stdout
      -- run action
      action
      -- load backup again
      hDuplicateTo stdout_old stdout
