MEV_BOOST = mev-boost
PRYSM = prysm
GETH = geth

.PHONY: all
all: node_modules $(GETH)/build/bin/geth $(PRYSM)/bazel-bin/cmd/beacon-chain/beacon-chain_/beacon-chain $(MEV_BOOST)/test-cli
ifeq (, $(shell which jq))
	$(error "No 'jq' binary found. Please install 'jq'.")
endif

node_modules:
	npm install

$(GETH)/build/bin/geth:
	wget https://github.com/ethereum/go-ethereum/archive/refs/tags/v1.10.23.tar.gz
	tar -xzf v1.10.23.tar.gz
	mv go-ethereum-1.10.23 $(GETH)
	make -C $(GETH)

$(PRYSM)/bazel-bin/cmd/beacon-chain/beacon-chain_/beacon-chain:
	git clone https://github.com/flashbots/prysm
	cd $(PRYSM) && \
		bazel build //cmd/beacon-chain:beacon-chain --config=release

$(MEV_BOOST)/test-cli:
	git clone https://github.com/flashbots/mev-boost
	make -C $(MEV_BOOST) build-testcli

.PHONY: clean
clean:
	rm -f v1.10.23.tar.gz*
	rm -rf $(GETH)
	rm -rf node_modules
	rm -rf $(PRYSM)/* $(PRYSM)/.[^.]*
	rm -rf $(MEV_BOOST)/* $(MEV_BOOST)/.[^.]*
