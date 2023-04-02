{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes       #-}

module Poseidon.SnapshotSpec (spec) where

import Poseidon.Snapshot (PoseidonPackageSnapshot (..), PackageState (..), writeSnapshot, readSnapshot, makeSnapshot, SnapshotMode (..))
import Poseidon.Package (dummyContributor, PackageReadOptions (..), defaultPackageReadOptions, readPoseidonPackageCollection)
import Poseidon.Utils (testLog)

import           Test.Hspec
import           Text.RawString.QQ
import qualified Data.ByteString.Char8      as B
import Data.Yaml (ParseException, decodeEither')
import Data.Version (makeVersion)
import Data.Time (fromGregorian)
import System.Directory (removeFile)

spec :: Spec
spec = do
    testSnapshotFromYaml
    testEncodeDecodeSnapshotFile
    testMakeSnapshot

yamlExampleSnapshot :: B.ByteString
yamlExampleSnapshot = [r|
title: Snapshot title
description: Snapshot description
contributor:
- name: Josiah Carberry
  email: carberry@brown.edu
  orcid: 0000-0002-1825-0097
snapshotVersion: 0.1.0
lastModified: 2023-04-02
packages:
- title: Lamnidis_2018
  version: 1.0.1
- title: Schiffels_2016
  version: 1.0.1
- title: Schmid_2028
  version: 1.0.0
- title: Wang_Plink_test_2020
  version: 0.1.0
|]

exampleSnapshot :: PoseidonPackageSnapshot
exampleSnapshot = PoseidonPackageSnapshot {
      snapYamlTitle           = Just "Snapshot title"
    , snapYamlDescription     = Just "Snapshot description"
    , snapYamlContributor     = [dummyContributor]
    , snapYamlSnapshotVersion = Just $ makeVersion [0, 1, 0]
    , snapYamlLastModified    = Just (fromGregorian 2023 04 02)
    , snapYamlPackages        = [
        PackageState {
              pacStateTitle   = "Lamnidis_2018"
            , pacStateVersion = Just $ makeVersion [1, 0, 1]
            , pacStateCommit  = Nothing
        },
        PackageState {
              pacStateTitle   = "Schiffels_2016"
            , pacStateVersion = Just $ makeVersion [1, 0, 1]
            , pacStateCommit  = Nothing
        },
        PackageState {
              pacStateTitle   = "Schmid_2028"
            , pacStateVersion = Just $ makeVersion [1, 0, 0]
            , pacStateCommit  = Nothing
        },
        PackageState {
              pacStateTitle   = "Wang_Plink_test_2020"
            , pacStateVersion = Just $ makeVersion [0, 1, 0]
            , pacStateCommit  = Nothing
        }
        ]
    }

testPacReadOpts :: PackageReadOptions
testPacReadOpts = defaultPackageReadOptions {
      _readOptStopOnDuplicates = False
    , _readOptIgnoreChecksums  = False
    , _readOptIgnoreGeno       = False
    , _readOptGenoCheck        = False
    }

testSnapshotFromYaml :: Spec
testSnapshotFromYaml = describe "Poseidon.Snapshot.fromYAML" $ do
    let (Right p) = decodeEither' yamlExampleSnapshot :: Either ParseException PoseidonPackageSnapshot
    it "should parse correct YAML data" $
        p `shouldBe` exampleSnapshot

testEncodeDecodeSnapshotFile :: Spec
testEncodeDecodeSnapshotFile = describe "Poseidon.Snapshot.writeSnapshot+readSnapshot" $ do
    let tmpFile = "/tmp/poseidonTestSnapshotFile"
    it "should write and read again correctly" $ do
        testLog $ writeSnapshot tmpFile exampleSnapshot
        res <- testLog $ readSnapshot tmpFile
        removeFile tmpFile
        res `shouldBe` exampleSnapshot

testMakeSnapshot :: Spec
testMakeSnapshot = describe "Poseidon.Snapshot.makeSnapshot" $ do
    it "should make a snapshot as expected" $ do
        pacs <- testLog $ readPoseidonPackageCollection testPacReadOpts ["test/testDat/testPackages/ancient"]
        snap <- testLog $ makeSnapshot SimpleSnapshot pacs
        snap `shouldBe` exampleSnapshot