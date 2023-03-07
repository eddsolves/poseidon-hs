module Poseidon.PoseidonVersion (
    validPoseidonVersions,
    showPoseidonVersion,
    latestPoseidonVersion,
    asVersion
) where

import           Data.Version (Version (..), makeVersion, showVersion)

newtype PoseidonVersion = PoseidonVersion Version
    deriving (Show, Eq, Ord)

validPoseidonVersions :: [PoseidonVersion]
validPoseidonVersions = map (PoseidonVersion . makeVersion) [[2,5,0], [2,6,0], [2,7,0]]

latestPoseidonVersion :: PoseidonVersion
latestPoseidonVersion = last validPoseidonVersions

asVersion :: PoseidonVersion -> Version
asVersion (PoseidonVersion x) = x

showPoseidonVersion :: PoseidonVersion -> String
showPoseidonVersion (PoseidonVersion x) = showVersion x
