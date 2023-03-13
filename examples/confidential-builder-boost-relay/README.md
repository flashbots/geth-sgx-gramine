# Confidential Block Building - Boost Relay communication PoC

This example showcases how searchers, builders and proposers can communicate in a confidential manner, making sure that the searchers bundles cannot be read by builder or proposer until its contents is finally committed to the chain. For this the builder runs MEV-Geth within SGX thus allowing the searcher to transmit its bundle confidentially with the builder unable to extract it from within the enclave. MEV-Geth builds a block including the bundle upon request by the proposer. First only the header of this block is submitted to the proposer. Only after the proposer signs the header and thus confirms that it will include the block in the chain, the block body is released from the enclave and made public.

### Build 

```
make -C examples/confidential-builder-boost-relay/

gramine-argv-serializer \
        ./geth_init \
                --goerli \
                --http \
                --http.api="eth,net,engine,web3,personal" \
                --authrpc.jwtsecret /etc/jwt.hex \
                --builder \
                --builder.local_relay \
                --builder.beacon_endpoint="http://127.0.0.1:3500" \
                --builder.bellatrix_fork_version="0x02001020" \
                --builder.genesis_fork_version="0x00001020" \
                --builder.genesis_validators_root="0x043db0d9a83813551ee2f33450d23797757d430911a9320530ad8a0eabc43efb" \
                --tls \
                --tlscert /tmp/tlscert.pem \
                --tlskey /tmp/tlskey.pem
        > geth.args

make SGX=1 TLS=1 ENCLAVE_SIZE=512G
```

> **IMPORTANT:** this will build [flashbots/prysm](https://github.com/flashbots/prysm), [ethereum/go-ethereum](https://github.com/ethereum/go-ethereum), [flashbots/mev-boost](https://github.com/flashbots/mev-boost) and [flashbots/geth-sgx-gramine](https://github.com/flashbots/geth-sgx-gramine). Make sure you have the required build and runtime dependencies installed.

### Generate [mev-boost test-cli](https://github.com/flashbots/mev-boost/tree/Main/cmd/test-cli) validator data

```
./examples/confidential-builder-boost-relay/mev-boost/test-cli generate
```

### Generate JWT secret

```
openssl rand -hex 32 | sudo tee /etc/jwt.hex
```

### Start [flashbots patched](https://github.com/flashbots/prysm) prysm

```
./examples/confidential-builder-boost-relay/prysm/bazel-bin/cmd/beacon-chain/beacon-chain_/beacon-chain \
      --accept-terms-of-use \
      --grpc-gateway-host=0.0.0.0 \
      --jwt-secret=/etc/jwt.hex \
      --execution-endpoint=http://127.0.0.1:8551 \
      --prater \
      --checkpoint-sync-url=https://goerli.checkpoint-sync.ethpandaops.io \
      --genesis-beacon-api-url=https://goerli.checkpoint-sync.ethpandaops.io
```

### Run geth directly and let it sync to head

Run geth as root so it can sync to /root/.ethereum

```
sudo ./geth/build/bin/geth --http \
      --goerli \
      --authrpc.jwtsecret /etc/jwt.hex
```


### After _stopping geth_, move database

```
sudo mv /root/.ethereum data/synced_state
```

### Start geth within SGX

```
env COPY_DATABASE="true" FAKE_PROPOSER="$(jq -r .Pk validator_data.json)" \
      gramine-sgx ./geth \
```

### Register validator

```
./examples/confidential-builder-boost-relay/mev-boost/test-cli register -mev-boost http://127.0.0.1:28545 -genesis-fork-version "0x00001020"
```


### After geth within SGX has succesfully synced to head, send searcher bundle

```
NODE_TLS_REJECT_UNAUTHORIZED=0 node examples/confidential-builder-boost-relay/move_flash.js
```

> **IMPORTANT:** Update MAIN_ADDRESS and MAIN_PRIVATE_KEY variables in `move_flash.js` with an address containing sufficient balance

### Request getHeader and getPayload once geth has included the bundle 

```
./examples/confidential-builder-boost-relay/mev-boost/test-cli getPayload -mev-boost http://127.0.0.1:28545 -genesis-fork-version "0x00001020" -bn http://localhost:3500  -genesis-validators-root "0xbf7e331f7f7c1dd2e05159666b3bf8bc7a8a3a9eb1d518969eab529dd9b88c1a" -bellatrix-fork-version "0x02001020"

```
