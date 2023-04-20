# Build Geth as follows:
#
# - make               -- create non-SGX no-debug-log manifest
# - make SGX=1         -- create SGX no-debug-log manifest
# - make SGX=1 DEBUG=1 -- create SGX debug-log manifest
#
# Any of these invocations clones Geth' git repository and builds Geth in
# default configuration.
#
# Use `make clean` to remove Gramine-generated files and `make distclean` to
# additionally remove the cloned Geth git repository.

################################# CONSTANTS ###################################

# directory with arch-specific libraries, used by Geth
# the below path works for Debian/Ubuntu; for CentOS/RHEL/Fedora, you should
# overwrite this default like this: `ARCH_LIBDIR=/lib64 make`
ARCH_LIBDIR ?= /lib/$(shell $(CC) -dumpmachine)

ENCLAVE_SIZE ?= 1024G

GETH_BRANCH ?= main
GETH_REPO ?= https://github.com/flashbots/builder

MBEDTLS_PATH = https://github.com/ARMmbed/mbedtls/archive/mbedtls-3.3.0.tar.gz

GPP = g++ -std=c++17
GORUN = env GO111MODULE=on go run
SRCDIR = go-ethereum

GOMODCACHE = $(shell go env GOMODCACHE)
PATCHED_GOLEVELDB = goleveldb

ifeq ($(DEBUG),1)
GRAMINE_LOG_LEVEL = debug
else
GRAMINE_LOG_LEVEL = error
endif

.PHONY: all
all: geth geth.manifest
ifeq ($(SGX),1)
all: geth_init geth.manifest.sgx geth.sig
endif

############################## GETH ARGUMENTS #################################

ifeq ($(MAINNET),1)
geth.args:
	gramine-argv-serializer \
		./geth_init \
			--vmodule='miner=4' \
			--metrics \
			--metrics.addr=127.0.0.1 \
			--metrics.builder \
			--metrics.expensive \
			--http \
			--http.api=engine,eth,web3,net,debug,flashbots,builder \
			--http.corsdomain=* \
			--http.addr=0.0.0.0 \
			--http.port=8545 \
			--http.vhosts=* \
			--ws \
			--ws.api=engine,eth,web3,net,debug \
			--ws.addr=0.0.0.0 \
			--ws.port=8546 \
			--ws.origins=* \
			--graphql \
			--graphql.corsdomain=* \
			--graphql.vhosts=* \
			--authrpc.jwtsecret=/etc/jwt.hex \
			--authrpc.vhosts=* \
			--authrpc.addr=0.0.0.0 \
			--builder \
			--builder.beacon_endpoints=http://127.0.0.1:3500,http://prysm:3500 \
			--builder.genesis_fork_version=0x00000000 \
			--builder.bellatrix_fork_version=0x02000000 \
			--builder.genesis_validators_root=0x0000000000000000000000000000000000000000000000000000000000000000 \
			--builder.remote_relay_endpoint=https://boost-relay.flashbots.net \
			--miner.extradata='Illuminate Dmocrtz Dstrib Prtct' \
			--miner.algotype=greedy \
			--cache.trie.journal= \
			--cache.trie.rejournal=0 \
			--datadir.ancient=/data/ancient \
		> $@
endif
ifeq ($(SEPOLIA),1)
geth.args:
	gramine-argv-serializer \
		./geth_init \
			--sepolia \
			--http \
			--http.api=engine,eth,web3,net,debug,flashbots \
			--http.corsdomain=* \
			--http.addr=0.0.0.0 \
			--ws \
			--ws.api=engine,eth,web3,net,debug \
			--authrpc.jwtsecret=/etc/jwt.hex \
			--authrpc.vhosts=* \
			--authrpc.addr=0.0.0.0 \
			--builder \
			--builder.beacon_endpoints=http://127.0.0.1:3500,http://prysm:3500 \
			--builder.genesis_fork_version=0x90000069 \
			--builder.bellatrix_fork_version=0x90000071 \
			--builder.genesis_validators_root=0xd8ea171f3c94aea21ebc42a1ed61052acf3f9209c00e4efbaaddac09ed9b8078 \
			--builder.remote_relay_endpoint=https://boost-relay-sepolia.flashbots.net \
			--miner.extradata='Illuminate Dmocrtz Dstrib Prtct' \
			--miner.algotype=greedy \
			--override.shanghai 1677557088 \
			--bootnodes=enode://9246d00bc8fd1742e5ad2428b80fc4dc45d786283e05ef6edbd9002cbc335d40998444732fbe921cb88e1d2c73d1b1de53bae6a2237996e9bfe14f871baf7066@18.168.182.86:30303,enode://ec66ddcf1a974950bd4c782789a7e04f8aa7110a72569b6e65fcd51e937e74eed303b1ea734e4d19cfaec9fbff9b6ee65bf31dcb50ba79acce9dd63a6aca61c7@52.14.151.177:30303 \
			--cache.trie.journal= \
			--cache.trie.rejournal=0 \
			--datadir.ancient=/data/ancient \
		> $@
endif

############################## GETH EXECUTABLE ###############################

# Clone Geth and fetch dependencies
$(SRCDIR)/Makefile:
	git clone -b $(GETH_BRANCH) $(GETH_REPO) $(SRCDIR)
	cd $(SRCDIR) && go mod download

# patch Geth
$(SRCDIR)/PATCHED: FLOCK_REVISION=$(shell git -C $(SRCDIR) merge-base --is-ancestor 09a9ccdbce HEAD && echo 1)
$(SRCDIR)/PATCHED: $(SRCDIR)/Makefile
	if [ 1 -eq $(FLOCK_REVISION) ]; then \
		patch -d $(SRCDIR) -p1 < geth-patches/0001a-go-ethereum.patch ; \
	else \
		patch -d $(SRCDIR) -p1 < geth-patches/0001-go-ethereum.patch ; \
	fi
ifeq ($(TLS),1)
	patch -d $(SRCDIR) -p1 < geth-patches/0003-go-ethereum-tls.patch
endif
ifeq ($(PROTECT),1)
	patch -d $(SRCDIR) -p1 < geth-patches/0004-protect.patch
endif
	touch $(SRCDIR)/PATCHED

# Create a local copy of goleveldb mod and patch it
$(PATCHED_GOLEVELDB): GOLEVELDB_SRCDIR=$(shell cat $(SRCDIR)/go.mod | awk -v pattern="goleveldb" '$$1 ~ pattern { print $$1 "@" $$2}')
$(PATCHED_GOLEVELDB): $(SRCDIR)/PATCHED
	cp -r --no-preserve=mode $(GOMODCACHE)/$(GOLEVELDB_SRCDIR) .
	mv $(PATCHED_GOLEVELDB)* $(PATCHED_GOLEVELDB)
	patch -d $(PATCHED_GOLEVELDB) -p1 < geth-patches/0002-goleveldb.patch

# Build Geth
$(SRCDIR)/build/bin/geth: $(PATCHED_GOLEVELDB)
	cd $(SRCDIR) && \
		go build -ldflags "-extldflags '-Wl,-z,stack-size=0x800000,-fuse-ld=gold'" -tags urfave_cli_no_docs -trimpath -v -o $(PWD)/$(SRCDIR)/build/bin/geth ./cmd/geth

################################## GETH INIT #################################

CFLAGS += $(shell pkg-config --cflags mbedtls_gramine)
LDFLAGS += -ldl -Wl,--enable-new-dtags $(shell pkg-config --libs mbedtls_gramine)

geth_init: geth_init.cpp
	$(GPP) $< $(CFLAGS) $(LDFLAGS) -o $@

##################### REMOTE ATTESTATION CLIENT ##############################

mbedtls:
	wget $(MBEDTLS_PATH) -O mbedtls.tgz
	mkdir mbedtls
	tar -xvzf mbedtls.tgz -C mbedtls --strip-components 1
	rm mbedtls.tgz

attest: attest.c mbedtls
	C_INCLUDE_PATH=mbedtls/include $(CC) $< $(CFLAGS) $(LDFLAGS) -o $@

################################ GETH MANIFEST ###############################

# The template file is a Jinja2 template and contains almost all necessary
# information to run Geth under Gramine / Gramine-SGX. We create
# geth.manifest (to be run under non-SGX Gramine) by replacing variables
# in the template file using the "gramine-manifest" script.

RA_TYPE		?= dcap
ISVPRODID	?= 0
ISVSVN		?= 0

geth.manifest: geth.manifest.template geth.args
	gramine-manifest \
		-Dlog_level=$(GRAMINE_LOG_LEVEL) \
		-Darch_libdir=$(ARCH_LIBDIR) \
		-Dentrypoint="./geth_init" \
		-Dgeth_bin="./geth" \
		-Dra_type=$(RA_TYPE) \
		-Disvprodid=$(ISVPRODID) \
		-Disvsvn=$(ISVSVN) \
		-Denclave_size=$(ENCLAVE_SIZE) \
		$< >$@

# Manifest for Gramine-SGX requires special "gramine-sgx-sign" procedure. This
# procedure measures all Geth trusted files, adds the measurement to the
# resulting manifest.sgx file (among other, less important SGX options) and
# creates geth.sig (SIGSTRUCT object).

# Make on Ubuntu <= 20.04 doesn't support "Rules with Grouped Targets" (`&:`),
# see the gramine helloworld example for details on this workaround.
geth.manifest.sgx geth.sig: sgx_sign
	@:

.INTERMEDIATE: sgx_sign
sgx_sign: geth.manifest
	gramine-sgx-sign \
		--manifest $< \
		--output $<.sgx

########################### COPIES OF EXECUTABLES #############################

# Geth build process creates the final executable as build/bin/geth. For
# simplicity, copy it into our root directory.

geth: $(SRCDIR)/build/bin/geth geth_init
	cp $< $@

############################## RUNNING TESTS ##################################

.PHONY: check
check: all
	./run-tests.sh > TEST_STDOUT 2> TEST_STDERR
	@grep -q "Success 1/4" TEST_STDOUT
	@grep -q "Success 2/4" TEST_STDOUT
	@grep -q "Success 3/4" TEST_STDOUT
	@grep -q "Success 4/4" TEST_STDOUT
ifeq ($(SGX),1)
	@grep -q "Success SGX quote" TEST_STDOUT
endif

################################## CLEANUP ####################################

.PHONY: clean
clean:
	$(RM) *.manifest *.manifest.sgx *.sig *.args OUTPUT* *.PID TEST_STDOUT TEST_STDERR

.PHONY: distclean
distclean: clean
	$(RM) -rf $(SRCDIR) $(PATCHED_GOLEVELDB) geth geth_init mbedtls attest
