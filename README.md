# Geth-in-SGX

This repository contains an example for running Geth in [Gramine](https://gramine.readthedocs.io/en/stable/), a libOS for SGX enclaves. It includes the Makefile, a template for generating the manifest and a small patch-set to make go-ethereum run in Gramine. A design decision was taken to store the complete geth database in memory via `tmpfs`. This decision was made for performance reasons but also to obfuscate IO access. Therefor the memory requirements of Geth-in-SGX are significant. It also means the database state does not persist after the application exits.

# Prerequisites

**OS:** Ubuntu 20.04, Linux Kernel >= 5.11

**go-ethereum:** v1.10.22 or newer

**Hardware:** CPU supporting SGX2 (Intel Skylake and newer), +64GB EPC Enclave Memory (for mainnet), +1TB Swap (for mainnet)

Follow the [Gramine Quickstart](https://gramine.readthedocs.io/en/stable/quickstart.html) in particular the sections [Install Gramine](https://gramine.readthedocs.io/en/stable/quickstart.html#install-gramine) and [Prepare a signing key](https://gramine.readthedocs.io/en/stable/quickstart.html#prepare-a-signing-key).

```
# install dependencies
sudo apt-get install -y libssl-dev gnupg software-properties-common build-essential ca-certificates git
```

# Generating the manifest

## Building for Linux

Run `make` (non-debug) or `make DEBUG=1` (debug) in the directory.

## Building for SGX

Run `make SGX=1` (non-debug) or `make SGX=1 DEBUG=1` (debug) in the directory.

## Enclave size

To change the amount of memory allocated to the enclave to 256 GB, run `make SGX=1 ENCLAVE_SIZE=256G`. Default is 1024 GB.

## Building with different Geth source repository

`go-ethereum` version `v1.10.22` and newer should compile without modification. Older versions need adaption of Makefile and go-ethereum patch-set. The patch-set contains minor changes to go-ethereum and the goleveldb dependencies which are required to run Geth in Gramine.

```
make GETH_BRANCH=master GETH_REPO=https://github.com/ethereum/go-ethereum
```

# Run Geth-in-SGX

Here's an example of running Geth under Gramine:
```
gramine-sgx ./geth --http --http.addr=0.0.0.0 --http.port=8545 --ws --ws.addr=0.0.0.0 --ws.port=8546 --goerli
```

To run Gramine in non-SGX (direct) mode, replace `gramine-sgx` with
`gramine-direct` and remove `SGX=1` in the commands above.

## Provide jwt secret file

The jwt secret file for authrpc communication is expected in the hard coded path `/etc/jwt.hex`. The path of the file still needs to be passed via argument input: `--authrpc.jwtsecret /etc/jwt.hex`

## Copy pre synced Geth Database

To copy an existing geth database into the enclave, set `COPY_DATABASE=true`. The existing database is currently expected in the hard coded path `/root/.ethereum.synced`
```
COPY_DATABASE=true gramine-sgx ./geth ...
```

## Configure Fake Validator

To test milestone two we can set a fake validator that will automatically be configured to always propose the next block.
```
FAKE_PROPOSER=0x.... gramine-sgx ./geth ...
```

## Running Enclave with memory size that does not fit in RAM

It is possible (and in case of running geth in mainnet - necessary) to run an SGX enclave where the enclave size is bigger than the systems RAM. In such situations, memory pages will get swapped out to a swap file. Make sure you have a big enough swap file mounted. The startup of the application will take much longer, since enclave pages must be EADDed. Depending on the System - especially how much (EPC) Memory is available - this can take more than an hour. To improve overall system responsivness, it is recommended to increase the `swapiness` kernel parameter.
```
sysctl vm.swappiness=80
```

# Attribution
Geth-SGX was developed and tested by [konVera](https://konvera.io) in collaboration with Flashbots
