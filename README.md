[![GitHub Workflow Status](https://img.shields.io/github/workflow/status/poseidon-framework/poseidon-hs/CI)](https://github.com/poseidon-framework/poseidon-hs/actions?query=workflow%3ACI)
[![Coverage Status](https://img.shields.io/codecov/c/github/poseidon-framework/poseidon-hs/master.svg)](https://codecov.io/github/poseidon-framework/poseidon-hs?branch=master)
[![GitHub release (latest by date including pre-releases)](https://img.shields.io/github/v/release/poseidon-framework/poseidon-hs?include_prereleases) ![GitHub all releases](https://img.shields.io/github/downloads/poseidon-framework/poseidon-hs/total)](https://github.com/poseidon-framework/poseidon-hs/releases)

# poseidon-hs
A toolset to work with modular genotype databases formatted using Poseidon. The main executable within this package is called `trident`.

**Detailed user documentation can be found on our github-page [here](https://poseidon-framework.github.io/#/trident).**

## For developers

The technical haddock documentation for the poseidon-hs Haskell library is available [here](https://poseidon-framework.github.io/poseidon-hs/index.html).

### Development Quickstart

You can install the internal documentation using `stack haddock` and open it subsequently using `stack haddock --open`. This will then open a HTML page with all dependency packages and the `poseidon-hs` library itself. The critical package is the `Poseidon.Package` module which defines the core functions to read and work with module files.

Important packages to look into to understand the architecture of this tool:

* Start with `Poseidon.Package`: It defines the main package format and provides some functions how to access the data inside packages.
* The `Poseidon.Utils` module only provides the definition of an Exception type.
* The modules in `CLI/` define the functionality provided in the command line functions for `trident`.
* The `list` command might be a good place to start understanding what's going on and how to use the `Poseidon.Package` interface.
* The `Poseidon.CmdFStats` module is a bit more involved, mainly due to the Jackknifing, which involves chunking up the genotype data as we run through it and compute F-Statistics in each block, and then summarising them again. This is all achieved in one go via the `Pipes.Group` technology.

### Preparing a new stable release

The Github Actions script in `.github/workflows/release.yml` registers a new draft release and automatically builds and uploads trident binaries when a new Git tag with the prefix `v*` is pushed. 

```bash
# locally register a new tag (e.g. 0.3.1)
git tag -a v0.3.1 -m "see CHANGELOG.md"
# push tag
git push origin v0.3.1
```

In case of a failing build delete the tag and the release draft on Github and then delete the tag locally with

```bash
git tag -d v0.3.1
```

before rerunning the procedure above.

### Golden tests

To test some of the output of the powerful trident CLI functions, poseidon-hs features a golden test mechanism:

The output of a number of CLI function calls implemented in [`test/Poseidon/GoldenTestsRunCommands.hs`](test/Poseidon/GoldenTestsRunCommands.hs) is stored in a static file storage ([`test/testDat/poseidonHSGoldenTestData`](test/testDat/poseidonHSGoldenTestData)), together with relevant checksums for these files in [`test/testDat/poseidonHSGoldenTestCheckSumFile.txt`](test/testDat/poseidonHSGoldenTestCheckSumFile.txt). 

`stack test` then runs -- among other things -- the code in `/test/testDat/poseidonHSGoldenTestData` again and stores the result in a dynamic, temporary directory. It then validates the output by comparing the new and temporary checksums with the old and git-logged checksums in said file `poseidonHSGoldenTestCheckSumFile.txt`. Any deviation between these two sets of checksums will cause the test to fail. The test output in this case will therefore only print the name of the operation or the output file that changed, not what exactly changed within this file. 

To find out what exactly changed and also update the output storage and static checksum file, you can run `poseidon-devtools updateGoldenTests` and compare the old and new static output storage with `git diff`.
