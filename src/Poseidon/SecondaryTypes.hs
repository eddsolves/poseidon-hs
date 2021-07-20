{-# LANGUAGE OverloadedStrings #-}

module Poseidon.SecondaryTypes (
    poseidonVersionParser,
    ContributorSpec (..),
    contributorSpecParser,
    IndividualInfo (..),
    VersionComponent (..)
) where

import           Data.Aeson             (FromJSON, ToJSON, object,
                                        parseJSON, toJSON, withObject,
                                        (.:), (.=))
import           Data.Version           (Version (..), makeVersion)
import qualified Text.Parsec            as P
import qualified Text.Parsec.String     as P

data VersionComponent = Major | Minor | Patch
    deriving Show

data IndividualInfo = IndividualInfo
    { indInfoName    :: String
    , indInfoGroup   :: String
    , indInfoPacName :: String
    }

instance ToJSON IndividualInfo where
    toJSON x = object [
        "name" .= indInfoName x,
        "group" .= indInfoGroup x,
        "pacName" .= indInfoPacName x]

instance FromJSON IndividualInfo where
    parseJSON = withObject "IndividualInfo" $ \v -> IndividualInfo
        <$> v .:   "name"
        <*> v .:   "group"
        <*> v .:  "pacName"

poseidonVersionParser :: P.Parser Version
poseidonVersionParser = do
    major <- read <$> P.many1 P.digit
    _ <- P.oneOf "."
    minor <- read <$> P.many1 P.digit
    _ <- P.oneOf "."
    patch <- read <$> P.many1 P.digit
    return (makeVersion [major, minor, patch])

-- | A data type to represent a contributor
data ContributorSpec = ContributorSpec
    { contributorName  :: String -- ^ the name of a contributor
    -- ^ the email address of a contributor
    , contributorEmail :: String -- ^ the email address of a contributor
    }
    deriving (Show, Eq)

-- | To facilitate automatic parsing of ContributorSpec from JSON files
instance FromJSON ContributorSpec where
    parseJSON = withObject "contributor" $ \v -> ContributorSpec
        <$> v .: "name"
        <*> v .: "email"

instance ToJSON ContributorSpec where
    -- this encodes directly to a bytestring Builder
    toJSON x = object [
        "name" .= contributorName x,
        "email" .= contributorEmail x
        ]

contributorSpecParser :: P.Parser [ContributorSpec]
contributorSpecParser = P.try (P.sepBy oneContributorSpecParser (P.char ';' <* P.spaces))

oneContributorSpecParser :: P.Parser ContributorSpec
oneContributorSpecParser = do
    name <- P.between (P.char '[') (P.char ']') (P.manyTill P.anyChar (P.lookAhead (P.char ']')))
    email <- P.between (P.char '(') (P.char ')') (P.manyTill P.anyChar (P.lookAhead (P.char ')')))
    return (ContributorSpec name email)