# Geth-in-SGX

This repository contains an example for running Geth in [Gramine](https://gramine.readthedocs.io/en/stable/), a libOS for SGX enclaves. It includes the Makefile, a template for generating the manifest and a small patch-set to make go-ethereum run in Gramine. A design decision was taken to store the complete geth database in memory via `tmpfs`. This decision was made for performance reasons but also to obfuscate IO access. Therefor the memory requirements of Geth-in-SGX are significant. It also means the database state does not persist after the application exits.

For more background and details, see also:

* https://writings.flashbots.net/block-building-inside-sgx ([discussion](https://collective.flashbots.net/t/block-building-inside-sgx/1373))
* https://writings.flashbots.net/geth-inside-sgx ([discussion](https://collective.flashbots.net/t/running-geth-within-sgx-our-experience-learnings-and-code-flashbots/938))

# Prerequisites

**OS:** Ubuntu 20.04, Linux Kernel >= 5.11

**go-ethereum:** v1.10.22 until v1.11.2 supported

**Hardware:** CPU supporting SGX2 (Intel Skylake and newer), +64GB EPC Enclave Memory (for mainnet), +1TB Swap (for mainnet)

Follow the [Gramine Quickstart](https://gramine.readthedocs.io/en/stable/quickstart.html) in particular the sections [Install Gramine](https://gramine.readthedocs.io/en/stable/quickstart.html#install-gramine) and [Prepare a signing key](https://gramine.readthedocs.io/en/stable/quickstart.html#prepare-a-signing-key).

## Build dependencies
```
sudo snap install --classic go
sudo apt-get install -y libssl-dev gnupg software-properties-common build-essential ca-certificates git
```

## Attestation dependencies

Attestation requires additional attestation infrastructure to be set up and configured. Enclaves running on Azure can make use of Azure's attestation infrastructure `a)`, whereas elsewhere, `b)` the attestation infrastructure including the provisioning certificate caching server (PCCS) needs to be set up and configured properly.

```
sudo apt-key adv --fetch-keys 'https://download.01.org/intel-sgx/sgx_repo/ubuntu/intel-sgx-deb.key'
sudo add-apt-repository "deb [arch=amd64] https://download.01.org/intel-sgx/sgx_repo/ubuntu `lsb_release -cs` main"
sudo apt-get update && sudo apt-get install -y libsgx-dcap-ql
```
### a) Azure cloud attestation
```
sudo apt-key adv --fetch-keys 'https://packages.microsoft.com/keys/microsoft.asc'
sudo apt-add-repository 'https://packages.microsoft.com/ubuntu/20.04/prod main'
sudo apt-get update && sudo apt-get install -y az-dcap-client
```
### b) Attestation via Intel - PCCS
```
sudo apt-get install -y libsgx-dcap-default-qpl sgx-dcap-pccs
```

# Builder Quickstart

> **IMPORTANT REQUIREMENTS:** Be sure to have a beacon-chain running, and a jwt secret configured at `/etc/jwt.hex`.

The instructions are tailored to Sepolia because of the minimal hardware requirements. The same instructions also work for a mainnet builder setup, although it's hardware requirements are much higher.

Generate the SGX signing key
```
gramine-sgx-gen-private-key
```

## Build Geth Enclanve
```
# Sepolia
make SGX=1 TLS=1 ENCLAVE_SIZE=64G SEPOLIA=1

# Mainnet
make SGX=1 TLS=1 ENCLAVE_SIZE=2048G MAINNET=1
```

## Start enclave
```
BUILDER_SECRET_KEY=<builder bls key> BUILDER_TX_SIGNING_KEY=<builder tx key> gramine-sgx ./geth
```

## Attest enclave

Extract measurements from Gramine signature
```
gramine-sgx-sigstruct-view geth.sig
```

Build the `attest` tool
```
make attest
```

Attest the enclave via the https endpoint
```
APPLICATION_HOST=<enclave host> APPLICATION_PORT=8545 ./attest dcap \
        <expected mrenclave> <expected mrsigner> <expected isv_prod_id> <expected isv_svn>
```

```
./attest dcap ce63bf3f3c29cb5b2c4f8ace497a602b4d3778d051922ba493dc08ebd0649ef3 39a3807530c976387e90a3134ea8bec28bcb4857e79db3ab5eb0e7df6996608e 0 0
[ using our own SGX-measurement verification callback (via command line options) ]
  - ignoring ISV_PROD_ID
  - ignoring ISV_SVN

  . Seeding the random number generator... ok
  . Connecting to tcp/localhost/8545... ok
  . Setting up the SSL/TLS structure... ok
 ok
  . Installing RA-TLS callback ... ok
  . Performing the SSL/TLS handshake... ok
  . Verifying peer X.509 certificate... ok
  > Write to server: 18 bytes written

GET / HTTP/1.0

  < Read from server: 89 bytes read

HTTP/1.0 200 OK
Vary: Origin
Date: Thu, 23 Feb 2023 15:18:57 GMT
Content-Length: 0
```

# Setting Geth Arguments

To be able to trust an instance of Geth running in SGX, Geth's arguments need to be attestable. To achieve this, the arguments are defined at build time and saved to a file, which is then added to the list of trusted files and thus part of the TCB.

```
gramine-argv-serializer \
        ./geth_init \
                --http \
                --ws \
                --authrpc.jwtsecret=/etc/jwt.hex \
        > geth.args
```

# Generating the manifest


## Important Makefile Environment Variables

| Variable       	| Default                                	| Description                                                                                                      	|
|----------------	|----------------------------------------	|------------------------------------------------------------------------------------------------------------------	|
| `SGX`          	| _empty_                                	| Creates files for `gramine-sgx` execution, if `SGX!=1`, files for `gramine-direct` execution are created         	|
| `DEBUG`        	| _empty_                                	| Controls Gramine's `DEBUG_LOG` verbosity, `1=='debug'`, else `'error'`                                           	|
| `ENCLAVE_SIZE` 	| `1024G`                                	| Amount of memory allocated to the enclave, `1024G` is the minimum amount required to fit the Ethereum mainnet DB 	|
| `GETH_REPO`    	| `https://github.com/flashbots/builder` 	| Location of the `go-ethereum` source code                                                                        	|
| `GETH_BRANCH`  	| `main`                                 	| `go-ethereum` branch                                                                                             	|
| `MAINNET`      	| _empty_                                	| Set to `1` to create a `geth.args` file for the default mainnet builder configuration                            	|
| `SEPOLIA`      	| _empty_                                	| Set to `1` to create a `geth.args` file for the default sepolia builder configuration                            	|
| `RA_TYPE`      	| `dcap`                                 	| Controls attestation functionality, set to `none` to disable                                                     	|
| `TLS`          	| _empty_                                	| Set to `1` to apply `go-ethereum` `RA-TLS` patch                                                                 	|
| `ISVPRODID`    	| `0`                                    	| Product ID of the Enclave                                                                                        	|
| `ISVSVN`       	| `0`                                    	| Security Version Number of the Enclave                                                                           	|

## Building for Linux

Run `make` (non-debug) or `make DEBUG=1` (debug) in the directory.

## Building for SGX

Run `make SGX=1` (non-debug) or `make SGX=1 DEBUG=1` (debug) in the directory.

## Building with different Geth source repository

`go-ethereum` version `v1.10.22` and newer should compile without modification. Older versions need adaption of Makefile and go-ethereum patch-set. The patch-set contains minor changes to go-ethereum and the goleveldb dependencies which are required to run Geth in Gramine.

# Run Geth-in-SGX

Run Geth under Gramine by executing this command:
```
gramine-sgx ./geth
```

To run Gramine in non-SGX (direct) mode, replace `gramine-sgx` with
`gramine-direct` and remove `SGX=1` in the commands above.

## Runtime environment variables

| Variable                 	| Default            	| Description                                                                                                                                                 	|
|--------------------------	|--------------------	|-------------------------------------------------------------------------------------------------------------------------------------------------------------	|
| `COPY_DATABASE`          	| _empty_            	| Set to `true`. Copies an existing geth database into the enclave. The existing database **must** be located in the hard coded path `data/synced_state/` 	|
| `FAKE_PROPOSER`          	| _empty_            	| Sets a fake validator that will automatically be configured to always propose the next block. Required for the `Boost Relay communication PoC`              	|
| `BUILDER_SECRET_KEY`     	| _empty_            	| Builder key used for signing blocks                                                                                                                         	|
| `BUILDER_TX_SIGNING_KEY` 	| _empty_            	| private key of the builder used to sign payment transaction, must be the same as the coinbase address                                                       	|
| `RATLS_CRT_PATH`         	| `/tmp/tlscert.der` 	| Location of the RA-TLS certificate. **Must** be set in the manifest at build time to be part of TCB                                                         	|
| `RATLS_KEY_PATH`         	| `/tmp/tlskey.der`  	| Location of the RA-TLS key. **Must** be set in the manifest at build time to be part of TCB                                                                 	|

## Provide jwt secret file

The jwt secret file for authrpc communication is expected in the hard coded path `/etc/jwt.hex`. The path of the file still needs to be passed via argument input: `--authrpc.jwtsecret /etc/jwt.hex`

## Running Enclave with memory size that does not fit in RAM

It is possible (and in case of running geth in mainnet - necessary) to run an SGX enclave where the enclave size is bigger than the systems RAM. In such situations, memory pages will get swapped out to a swap file. Make sure you have a big enough swap file mounted. To improve overall system responsivness, it is recommended to increase the `swapiness` kernel parameter.
```
sysctl vm.swappiness=80
```

# Attestation

Recommended reading: [Gramine attestation docs](https://gramine.readthedocs.io/en/stable/attestation.html)

## How does the attestation work?
Gramine's RA-TLS implementation is used to provide a convenient way of attestation and secure communication with the Geth node. RA-TLS integrates Intel SGX remote attestation into the TLS connection setup. Conceptually, it extends the standard X.509 certificate with SGX-related information (SGX quote). The additional information allows the remote user (verifier) of the certificate to verify that it is indeed communicating with an SGX enclave (attester).

The RA-TLS certificate is created by default on startup. Attestation functionality can be disabled via the `RA_TYPE` environment variable.

Only DCAP attestation is supported, legacy EPID attestation is **not supported**.

## Attestation verification

Attestation verification requires `4` values: `mrenclave` ,`mrsigner`, `isv_prod_id`, `isv_svn`. They can be extracted from the Gramine signature with the help of the `gramine-sgx-sigstruct-view` tool.
```
gramine-sgx-sigstruct-view geth.sig
```

Build the `attest` tool to verify a `RA-TLS` connection.
```
make attest
```

Attest the enclave via a connection that serves the `RA-TLS` certificate.
```
APPLICATION_HOST=<enclave host> APPLICATION_PORT=<enclave port> ./attest dcap \
        <expected mrenclave> <expected mrsigner> <expected isv_prod_id> <expected isv_svn>
```

## Using the RA-TLS certificate within Geth

Geth does not have https endpoints by default. The `TLS` environment variable can be set at build time to apply a simple patch to `go-ethereum`, which will wrap a TLS layer around Geths `http` and `ws` endpoints. The TLS connection is automatically configured to serve the `RA-TLS` certificate created on startup.

It is also possible to create a TLS implementation from scratch. `RATLS_CRT_PATH` and `RATLS_KEY_PATH` environment variables control the file locations and are passed to `geth_init`, which creates key and certificate at said location. The environment variables are subsequently passed on when starting Geth.

# Attribution
Geth-SGX is developed and tested by [konVera](https://konvera.io) in collaboration with Flashbots
