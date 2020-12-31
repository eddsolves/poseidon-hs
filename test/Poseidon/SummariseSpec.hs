module Poseidon.SummariseSpec (spec) where

import           Poseidon.CLI.Summarise

import           Data.Maybe             (Maybe(..))
import           Test.Hspec

spec = do
    testPasteFirstN
    testFrequency
    testPrintFrequency
    testPrintFrequencyMaybe
    testMaybeShow

testPasteFirstN :: Spec
testPasteFirstN = 
    describe "Poseidon.CLI.Summarise.pasteFirstN" $ do
    it "should deal with an empty list correctly" $ do
        pasteFirstN 123 [] `shouldBe` "no values"
    it "should concat 1/1 correctly" $ do
        pasteFirstN 1 ["a"] `shouldBe` "a"
    it "should concat 2/1 correctly" $ do
        pasteFirstN 2 ["a"] `shouldBe` "a"
    it "should concat 1/2 correctly" $ do
        pasteFirstN 1 ["a", "b"] `shouldBe` "a, ..."
    it "should concat 2/2 correctly" $ do
        pasteFirstN 2 ["a", "b"] `shouldBe` "a, b"

testFrequency :: Spec
testFrequency = 
    describe "Poseidon.CLI.Summarise.frequency" $ do
    it "should calculate frequencies correctly for strings" $ do
        frequency ["ab", "bc", "cd", "cd", "ab"] `shouldBe` 
            [("ab", 2), ("bc", 1), ("cd", 2)]
    it "should calculate frequencies correctly for integers" $ do
        frequency [1, 2, 3, 1, 1] `shouldBe` 
            [(1, 3), (2, 1), (3, 1)]

testPrintFrequency :: Spec
testPrintFrequency = 
    describe "Poseidon.CLI.Summarise.printFrequency" $ do
    it "should deal with an empty list correctly" $ do
        printFrequency ":-)" ([] :: [(Int, Int)]) `shouldBe` "no values"
    it "should display frequencies correctly for strings" $ do
        printFrequency ", " (frequency ["ab", "bc", "cd", "cd", "ab"]) `shouldBe` 
            "\"ab\": 2, \"bc\": 1, \"cd\": 2"
    it "should display frequencies correctly for integers" $ do
        printFrequency " | " (frequency [1, 2, 3, 1, 1]) `shouldBe` 
            "1: 3 | 2: 1 | 3: 1"

testPrintFrequencyMaybe :: Spec
testPrintFrequencyMaybe = 
    describe "Poseidon.CLI.Summarise.printFrequencyMaybe" $ do
    it "should deal with an empty list correctly" $ do
        printFrequencyMaybe ":-)" ([] :: [(Maybe Int, Int)]) `shouldBe` "no values"
    it "should deal with an effectivly empty list correctly" $ do
        printFrequencyMaybe ":-)" ([(Nothing, 3)] :: [(Maybe Int, Int)]) `shouldBe` "no values"
    it "should display frequencies correctly for strings" $ do
        printFrequencyMaybe ", " (frequency [Just "ab", Just "bc", Nothing, Just "ab"]) `shouldBe` 
            "n/a: 1, \"ab\": 2, \"bc\": 1"
    it "should display frequencies correctly for integers" $ do
        printFrequencyMaybe " | " (frequency [Just 1, Just 2, Nothing, Just 1, Nothing]) `shouldBe` 
            "n/a: 2 | 1: 2 | 2: 1"

testMaybeShow :: Spec
testMaybeShow = 
    describe "Poseidon.CLI.Summarise.maybeShow" $ do
    it "should" $ do
        1 `shouldBe` 1