{-# LANGUAGE DeriveGeneric #-}

module Poseidon.CmdSummarise (runSummarise, SummariseOptions(..)) where

import           Poseidon.Package   (loadPoseidonPackages,
                                    loadJannoFiles,
                                    PoseidonPackage(..), 
                                    PoseidonSample(..),
                                    Percent(..))
import           Poseidon.Utils     (printPoseidonJannoException)

import qualified Data.Either        as E
import           Data.Maybe         (catMaybes)
import qualified Data.List          as L
import           System.IO          (hPutStrLn, stderr)

-- | A datatype representing command line options for the summarise command
data SummariseOptions = SummariseOptions
    { _jaBaseDirs  :: [FilePath]
    }

-- | The main function running the janno command
runSummarise :: SummariseOptions -> IO ()
runSummarise (SummariseOptions baseDirs) = do 
    packages <- loadPoseidonPackages baseDirs
    hPutStrLn stderr $ (show . length $ packages) ++ " Poseidon packages found"
    let jannoFilePaths = map posPacJannoFile packages
    jannoSamples <- fmap concat . loadJannoFiles $ jannoFilePaths
    -- show all parsing errors
    mapM_ printPoseidonJannoException (E.lefts jannoSamples)
    -- show actual summary
    summarisePoseidonSamples (E.rights jannoSamples)

-- | A function to print meaningful summary information for a list of poseidon samples
summarisePoseidonSamples :: [PoseidonSample] -> IO ()
summarisePoseidonSamples xs = do
    putStrLn "---"
    putStrLn $ "Number of samples:\t" ++ 
                show (length xs)
    putStrLn $ "Individuals:\t\t" ++ 
                pasteFirstN 5 (map posSamIndividualID xs)
    putStrLn $ "Sex distribution:\t" ++ 
                printFrequency ", " (frequency (map posSamGeneticSex xs))
    putStrLn $ "Populations:\t\t" ++ 
                pasteFirstN 2 (L.nub $ map (head . posSamGroupName) xs)
    putStrLn $ "Publications:\t\t" ++ 
                pasteFirstN 2 (L.nub $ catMaybes $ map posSamPublication xs)
    putStrLn $ "Countries:\t\t" ++ 
                pasteFirstN 5 (L.nub $ catMaybes $ map posSamCountry xs)
    putStrLn $ "Mean age BC/AD:\t\t" ++ 
               meanAndSdInteger (map fromIntegral (catMaybes $ map posSamDateBCADMedian xs))
    putStrLn $ "Dating type:\t\t" ++ 
                printFrequencyMaybe ", " (frequency (map posSamDateType xs))
    putStrLn "---"
    putStrLn $ "MT haplogroups:\t\t" ++ 
                pasteFirstN 5 (L.nub $ catMaybes $ map posSamMTHaplogroup xs)
    putStrLn $ "Y haplogroups:\t\t" ++ 
                pasteFirstN 5 (L.nub $ catMaybes $ map posSamYHaplogroup xs)
    putStrLn $ "% endogenous human DNA:\t" ++ 
                meanAndSdRoundTo 2 (map (\(Percent x) -> x) (catMaybes $ map posSamEndogenous xs))
    putStrLn $ "# of SNPs on 1240K:\t" ++ 
                meanAndSdInteger (map fromIntegral (catMaybes $ map posSamNrAutosomalSNPs xs))
    putStrLn $ "Coverage on 1240K:\t" ++ 
                meanAndSdRoundTo 2 (catMaybes $ map posSamCoverage1240K xs)
    putStrLn $ "Library type:\t\t" ++ 
                printFrequencyMaybe ", " (frequency (map posSamLibraryBuilt xs))
    putStrLn $ "UDG treatment:\t\t" ++ 
                printFrequencyMaybe ", " (frequency (map posSamUDG xs))

-- | A helper function to concat the first N elements of a string list in a nice way
pasteFirstN :: Int -> [String] -> String
pasteFirstN _ [] = "no values"
pasteFirstN n xs = 
    (L.intercalate ", " $ take n xs) ++ if (length xs > n) then ", ..." else ""

-- | A helper function to calculate the mean of a list of doubles
avg :: [Double] -> Double
avg xs = let sum = L.foldl' (+) 0 xs
         in sum / fromIntegral (length xs)

-- | A helper function to round doubles
roundTo :: Int -> Double -> Double
roundTo n x = fromIntegral (floor (x * t)) / t
    where t = 10^n

-- | A helper function to calculate the standard deviation of a list of doubles
stdev :: [Double] -> Double
stdev xs = sqrt . avg . map ((^2) . (-) (avg xs)) $ xs

-- | A helper function to get a nice string with mean and sd for a list of doubles
meanAndSdRoundTo :: Int -> [Double] -> String
meanAndSdRoundTo n xs = (show $ roundTo n $ avg xs) ++ " ± " ++ (show $ roundTo n $ stdev xs)

-- | A helper function to get a nice string with mean and sd for a list of doubles 
-- (here rounded to integer)
meanAndSdInteger :: [Double] -> String
meanAndSdInteger xs = (show $ round $ avg xs) ++ " ± " ++ (show $ round $ stdev xs)

-- | A helper function to determine the frequency of objects in a list 
-- (similar to the table function in R)
frequency :: Ord a => [a] -> [(a,Int)] 
frequency list = map (\l -> (head l, length l)) (L.group (L.sort list))

-- | A helper function to print the output of frequency nicely
printFrequency :: Show a => String -> [(a,Int)] -> String
printFrequency _ [] = ""
printFrequency _ [x] = show (fst x) ++ ": " ++ show (snd x)
printFrequency sep (x:xs) = show (fst x) ++ ": " ++ show (snd x) ++ sep ++ printFrequency sep xs

-- | A helper function to print the output of frequency over Maybe values nicely
printFrequencyMaybe :: Show a => String -> [(Maybe a,Int)] -> String
printFrequencyMaybe _ [] = ""
printFrequencyMaybe _ [x] = maybeShow (fst x) ++ ": " ++ show (snd x)
printFrequencyMaybe sep (x:xs) = maybeShow (fst x) ++ ": " ++ show (snd x) ++ sep ++ printFrequencyMaybe sep xs

-- | A helper function to unwrap a maybe
maybeShow :: Show a => Maybe a -> String
maybeShow (Just x) = show x
maybeShow Nothing  = "n/a"
