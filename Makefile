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

GETH_SRCDIR = go-ethereum
GETH_BRANCH ?= master
GETH_REPO ?= https://github.com/flashbots/mev-geth

MARBLERUN_SRCDIR = marblerun
MARBLERUN_REPO = https://github.com/edgelesssys/marblerun.git

GPP = g++ -std=c++17
GORUN = env GO111MODULE=on go run

GOMODCACHE = $(shell go env GOMODCACHE)
PATCHED_GOLEVELDB = goleveldb

ifeq ($(DEBUG),1)
GRAMINE_LOG_LEVEL = debug
else
GRAMINE_LOG_LEVEL = error
endif

.PHONY: all
all: geth premain-libos geth.manifest marblerun-manifest.goerli.json
ifeq ($(SGX),1)
all: geth_init premain-libos geth.manifest.sgx geth.sig geth.token marblerun-manifest.goerli.json
endif
ifeq (, $(shell which jq))
        $(error "No 'jq' binary found. Please install 'jq'.")
endif

########################## MARBLERUN PREMAIN ##################################

$(MARBLERUN_SRCDIR)/Makefile:
	git clone $(MARBLERUN_REPO) $(MARBLERUN_SRCDIR)

$(MARBLERUN_SRCDIR)/premain-libos: $(MARBLERUN_SRCDIR)/Makefile
	cd $(MARBLERUN_SRCDIR) && \
		. /opt/edgelessrt/share/openenclave/openenclaverc && \
		cmake -DCMAKE_BUILD_TYPE=RelWithDebInfo . && \
		make premain-libos

############################## GETH EXECUTABLE ###############################

# Clone Geth, fetch dependencies and patch Geth 
$(GETH_SRCDIR)/Makefile:
	git clone -b $(GETH_BRANCH) $(GETH_REPO) $(GETH_SRCDIR)
	cd $(GETH_SRCDIR) && \
		go mod download && \
		patch -p1 < ../gramine-compatibility/0001-go-ethereum.patch

# Create a local copy of goleveldb mod and patch it
$(PATCHED_GOLEVELDB): GOLEVELDB_SRCDIR=$(shell cat $(GETH_SRCDIR)/go.mod | awk -v pattern="goleveldb" '$$1 ~ pattern { print $$1 "@" $$2}')
$(PATCHED_GOLEVELDB): $(GETH_SRCDIR)/Makefile
	cp -r --no-preserve=mode $(GOMODCACHE)/$(GOLEVELDB_SRCDIR) .
	mv $(PATCHED_GOLEVELDB)* $(PATCHED_GOLEVELDB)
	cd $(PATCHED_GOLEVELDB) && \
                patch -p1 < ../gramine-compatibility/0002-goleveldb.patch

# Build Geth
$(GETH_SRCDIR)/build/bin/geth: $(PATCHED_GOLEVELDB)
	cd $(GETH_SRCDIR) && \
		$(GORUN) build/ci.go install -static ./cmd/geth

################################## GETH INIT #################################

geth_init: geth_init.cpp
	$(GPP) -o geth_init geth_init.cpp

################################ GETH MANIFEST ###############################

# The template file is a Jinja2 template and contains almost all necessary
# information to run Geth under Gramine / Gramine-SGX. We create
# geth.manifest (to be run under non-SGX Gramine) by replacing variables
# in the template file using the "gramine-manifest" script.

RA_CLIENT_LINKABLE ?= 0
ISVPRODID          ?= 13
ISVSVN             ?= 1

geth.manifest: geth.manifest.template
	gramine-manifest \
		-Dlog_level=$(GRAMINE_LOG_LEVEL) \
		-Darch_libdir=$(ARCH_LIBDIR) \
		-Dentrypoint="./geth_init" \
		-Dgeth_bin="./geth" \
		-Dra_client_linkable=$(RA_CLIENT_LINKABLE) \
		-Disvprodid=$(ISVPRODID) \
		-Disvsvn=$(ISVSVN) \
		-Denclave_size=$(ENCLAVE_SIZE) \
		$< >$@

# Manifest for Gramine-SGX requires special "gramine-sgx-sign" procedure. This
# procedure measures all Geth trusted files, adds the measurement to the
# resulting manifest.sgx file (among other, less important SGX options) and
# creates geth.sig (SIGSTRUCT object).
#
# Gramine-SGX requires EINITTOKEN and SIGSTRUCT objects (see SGX hardware ABI,
# in particular EINIT instruction). The "gramine-sgx-get-token" script
# generates EINITTOKEN based on a SIGSTRUCT and puts it in .token file. Note
# that filenames must be the same as the manifest name (i.e., "geth").

# Make on Ubuntu <= 20.04 doesn't support "Rules with Grouped Targets" (`&:`),
# see the gramine helloworld example for details on this workaround.
geth.manifest.sgx geth.sig: sgx_sign
	@:

.INTERMEDIATE: sgx_sign
sgx_sign: geth.manifest
	gramine-sgx-sign \
		--manifest $< \
		--output $<.sgx

geth.token: geth.sig
	gramine-sgx-get-token --output $@ --sig $<

############################ MARBLERUN MANIFEST ###############################

marblerun-manifest.goerli.json: MR_SIGNER=$(shell gramine-sgx-get-token -s geth.sig -o /dev/null | awk -v pattern="mr_signer" '$$1 ~ pattern { print $$2 }')
marblerun-manifest.goerli.json: geth.sig
	jq ".Packages.\"geth-package\".SignerID = \"$(MR_SIGNER)\"" marblerun-manifest.goerli.json.template > marblerun-manifest.goerli.json

########################### COPIES OF EXECUTABLES #############################

# Geth build process creates the final executable as build/bin/geth. For
# simplicity, copy it into our root directory.

geth: $(GETH_SRCDIR)/build/bin/geth geth_init
	cp $< $@

premain-libos: $(MARBLERUN_SRCDIR)/premain-libos
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
	$(RM) *.manifest *.manifest.sgx *.token *.sig OUTPUT* *.PID TEST_STDOUT TEST_STDERR

.PHONY: distclean
distclean: clean
	$(RM) -rf $(GETH_SRCDIR) $(MARBLERUN_SRCDIR) $(PATCHED_GOLEVELDB) geth geth_init
