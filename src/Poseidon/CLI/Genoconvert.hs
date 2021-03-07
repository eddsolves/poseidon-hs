module Poseidon.CLI.Genoconvert where

import           Poseidon.GenotypeData      (GenotypeDataSpec (..),
                                             GenotypeFormatSpec (..),
                                             loadGenotypeData)
import           Poseidon.Package           (findAllPoseidonYmlFiles,
                                             readPoseidonPackageCollection,
                                             PoseidonPackage (..))

import           Control.Monad              (when)
import           Pipes                      (MonadIO (liftIO), Pipe (..), await,
                                             lift, runEffect, yield, (>->))
import qualified Pipes.Prelude              as P
import           Pipes.Safe                 (SafeT (..), runSafeT, throwM)
import           SequenceFormats.Eigenstrat (EigenstratIndEntry (..),
                                             EigenstratSnpEntry (..), GenoLine,
                                             writeEigenstrat)
import           SequenceFormats.Plink      (writePlink)
import           System.Console.ANSI        (hClearLine, hSetCursorColumn)
import           System.FilePath            ((<.>), (</>))
import           System.IO                  (hFlush, hPutStr, hPutStrLn, stderr)

-- | A datatype representing command line options for the validate command
data GenoconvertOptions = GenoconvertOptions
    { _baseDirs :: [FilePath]
    , _outFormat :: GenotypeFormatSpec
    }

runGenoconvert :: GenoconvertOptions -> IO ()
runGenoconvert (GenoconvertOptions baseDirs outFormat) = do
    -- load packages
    allPackages <- readPoseidonPackageCollection True False baseDirs
    -- convert
    mapM_ (convertGenoTo outFormat) allPackages

convertGenoTo :: GenotypeFormatSpec -> PoseidonPackage -> IO ()
convertGenoTo outFormat pac = do
    -- start message
    hPutStrLn stderr $
        "Converting genotype data in package "
        ++ posPacTitle pac
        ++ " to format "
        ++ show outFormat
        ++ ":"
    -- compile file names paths
    let outName = posPacTitle pac
    let [outInd, outSnp, outGeno] = case outFormat of 
            GenotypeFormatEigenstrat -> [outName <.> ".ind", outName <.> ".snp", outName <.> ".geno"]
            GenotypeFormatPlink -> [outName <.> ".fam", outName <.> ".bim", outName <.> ".bed"]
    if format (posPacGenotypeData pac) /= outFormat
    then do
        runSafeT $ do
            (eigenstratIndEntries, eigenstratProd) <- loadGenotypeData (posPacBaseDir pac) (posPacGenotypeData pac)
            let [outG, outS, outI] = map (posPacBaseDir pac </>) [outGeno, outSnp, outInd]
            let outConsumer = case outFormat of
                    GenotypeFormatEigenstrat -> writeEigenstrat outG outS outI eigenstratIndEntries
                    GenotypeFormatPlink -> writePlink outG outS outI eigenstratIndEntries
            runEffect $ eigenstratProd >-> printProgress >-> outConsumer
            liftIO $ hClearLine stderr
            liftIO $ hSetCursorColumn stderr 0
            liftIO $ hPutStrLn stderr "SNPs processed: All done"
    else hPutStrLn stderr 
        "The genotype data is already in the requested format"
        
printProgress :: Pipe a a (SafeT IO) ()
printProgress = loop 0
  where
    loop n = do
        when (n `rem` 1000 == 0) $ do
            liftIO $ hClearLine stderr
            liftIO $ hSetCursorColumn stderr 0
            liftIO $ hPutStr stderr ("SNPs processed: " ++ show n)
            liftIO $ hFlush stderr
        x <- await
        yield x
        loop (n+1)