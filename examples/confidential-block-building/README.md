# Confidential Block Building

This example showcases how searchers, builders and proposers can communicate in a confidential manner, making sure that the searchers bundles cannot be read by builder or proposer until its contents is finally committed to the chain. For this the builder runs MEV-Geth within SGX thus allowing the searcher to transmit its bundle confidentially with the builder unable to extract it from within the enclave. MEV-Geth builds a block including the bundle upon request by the proposer. First only the header of this block is submitted to the proposer. Only after the proposer signs the header and thus confirms that it will include the block in the chain, the block body is released from the enclave and made public.

### Build 

```
make

cd ../../

make GETH_REPO=https://gitlab.com/konvera/flashbots/mev-geth-sgx GETH_BRANCH=mev-geth-v1.10.23-mev0.6.2-tls-support-attestation SGX=1 ENCLAVE_SIZE=256G
```

> **IMPORTANT:** this will build [flashbots/prysm](https://github.com/flashbots/prysm), [ethereum/go-ethereum](https://github.com/ethereum/go-ethereum), [flashbots/mev-boost](https://github.com/flashbots/mev-boost) and [flashbots/geth-sgx-gramine](https://github.com/flashbots/geth-sgx-gramine). Make sure you have the required build and runtime dependencies installed.

### Generate [mev-boost test-cli](https://github.com/flashbots/mev-boost/tree/Main/cmd/test-cli) validator data

```
./mev-boost/test-cli generate
```

### Generate JWT secret

```
openssl rand -hex 32 | sudo tee /etc/jwt.hex
```

### Start [flashbots patched](https://github.com/flashbots/prysm) prysm

```
./prysm/bazel-bin/cmd/beacon-chain/beacon-chain_/beacon-chain \
      --accept-terms-of-use \
      --grpc-gateway-host=0.0.0.0 \
      --jwt-secret=/etc/jwt.hex \
      --execution-endpoint=http://127.0.0.1:8551 \
      --prater \
      --checkpoint-sync-url=https://goerli.checkpoint-sync.ethpandaops.io \
      --genesis-beacon-api-url=https://goerli.checkpoint-sync.ethpandaops.io
```

### Run upstream geth and let it sync to head

Run geth as root so it can sync to /root/.ethereum

```
sudo ./geth/build/bin/geth --http \
      --goerli \
      --authrpc.jwtsecret /etc/jwt.hex
```


### After _stopping upstream geth_, move database

```
sudo mv /root/.ethereum /root/.ethereum.synced
```

### Start and configure Marblerun Coordinator

```
# source the openenclaverc file to setup environment variables
. /opt/edgelessrt/share/openenclave/openenclaverc

# install marblerun CLI
wget -P ~/.local/bin https://github.com/edgelesssys/marblerun/releases/latest/download/marblerun
chmod +x ~/.local/bin/marblerun

# download marblerun coordinator
wget https://github.com/edgelesssys/marblerun/releases/latest/download/coordinator-enclave.signed

# start coordinator
erthost coordinator-enclave.signed

# remote attestation of marblerun coordinator, extract coordinator CA chain
export MARBLERUN=localhost:4433
marblerun certificate chain $MARBLERUN -o marblerun.crt

# set marblerun manifest and confirm manifest status is "ready to accept marbles"
marblerun manifest set marblerun-manifest.goerli.json $MARBLERUN
marblerun status $MARBLERUN
```

### Start geth within SGX

Run gramine as root so it can access /root/.ethereum.synced

```
cd ../../
sudo env COPY_DATABASE="true" FAKE_PROPOSER="$(jq -r .Pk ../validator_data.json)" gramine-sgx ./geth
```

> **NOTE:** geth command line arguments need to be provided via the marbelrun manifest and cannot be passed during start of the application. The reason for this is that the command line arguments need to be attested as well.

### Register validator

```
./mev-boost/test-cli register -mev-boost http://127.0.0.1:28545 -genesis-fork-version "0x00001020"
```


### After geth within SGX has succesfully synced to head, send searcher bundle

By making sure we are trusting _only_ the marblerun coordinator CA chain while establishing the TLS connection we can be sure we are communicating with an enclave that has been attested by the marblerun coordinator to reflect exactly the properties as described within the marblerun manifest.

```
NODE_EXTRA_CA_CERTS=marblerun.crt node move_flash.js
```

> **IMPORTANT:** Update MAIN_ADDRESS and MAIN_PRIVATE_KEY variables in `move_flash.js` with an address containing sufficient balance

### Request getHeader and getPayload once geth has included the bundle 

```
./mev-boost/test-cli getPayload -mev-boost http://127.0.0.1:28545 -genesis-fork-version "0x00001020" -bn http://localhost:3500  -genesis-validators-root "0xbf7e331f7f7c1dd2e05159666b3bf8bc7a8a3a9eb1d518969eab529dd9b88c1a" -bellatrix-fork-version "0x02001020"
```
