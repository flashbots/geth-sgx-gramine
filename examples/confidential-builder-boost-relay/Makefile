MEV_BOOST = mev-boost
PRYSM = prysm

.PHONY: all
all: node_modules $(PRYSM)/bazel-bin/cmd/beacon-chain/beacon-chain_/beacon-chain $(MEV_BOOST)/test-cli
ifeq (, $(shell which jq))
	$(error "No 'jq' binary found. Please install 'jq'.")
endif

node_modules:
	npm install

$(PRYSM)/bazel-bin/cmd/beacon-chain/beacon-chain_/beacon-chain:
	git clone https://github.com/flashbots/prysm
	cd $(PRYSM) && \
		bazel build //cmd/beacon-chain:beacon-chain --config=release

$(MEV_BOOST)/test-cli:
	git clone https://github.com/flashbots/mev-boost
	make -C $(MEV_BOOST) build-testcli

.PHONY: clean
clean:
	rm -rf node_modules
	rm -rf $(PRYSM)/* $(PRYSM)/.[^.]*
	rm -rf $(MEV_BOOST)/* $(MEV_BOOST)/.[^.]*
