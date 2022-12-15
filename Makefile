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

GETH_BRANCH ?= master
GETH_REPO ?= https://github.com/flashbots/mev-geth

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
all: geth_init geth.manifest.sgx geth.sig geth.token
endif

############################## GETH EXECUTABLE ###############################

# Clone Geth, fetch dependencies and patch Geth 
$(SRCDIR)/Makefile:
	git clone -b $(GETH_BRANCH) $(GETH_REPO) $(SRCDIR)
	cd $(SRCDIR) && \
		go mod download && \
		patch -p1 < ../gramine-compatibility/0001-go-ethereum.patch

# Create a local copy of goleveldb mod and patch it
$(PATCHED_GOLEVELDB): GOLEVELDB_SRCDIR=$(shell cat $(SRCDIR)/go.mod | awk -v pattern="goleveldb" '$$1 ~ pattern { print $$1 "@" $$2}')
$(PATCHED_GOLEVELDB): $(SRCDIR)/Makefile
	cp -r --no-preserve=mode $(GOMODCACHE)/$(GOLEVELDB_SRCDIR) .
	mv $(PATCHED_GOLEVELDB)* $(PATCHED_GOLEVELDB)
	cd $(PATCHED_GOLEVELDB) && \
                patch -p1 < ../gramine-compatibility/0002-goleveldb.patch

# Build Geth
$(SRCDIR)/build/bin/geth: $(PATCHED_GOLEVELDB)
	cd $(SRCDIR) && \
		$(GORUN) build/ci.go install -static ./cmd/geth

################################## GETH INIT #################################

geth_init: geth_init.cpp
	$(GPP) -o geth_init geth_init.cpp

################################ GETH MANIFEST ###############################

# The template file is a Jinja2 template and contains almost all necessary
# information to run Geth under Gramine / Gramine-SGX. We create
# geth.manifest (to be run under non-SGX Gramine) by replacing variables
# in the template file using the "gramine-manifest" script.

RA_TYPE ?= none
RA_CLIENT_SPID ?=
RA_CLIENT_LINKABLE ?= 0

geth.manifest: geth.manifest.template
	gramine-manifest \
		-Dlog_level=$(GRAMINE_LOG_LEVEL) \
		-Darch_libdir=$(ARCH_LIBDIR) \
		-Dentrypoint="./geth_init" \
		-Dgeth_bin="./geth" \
		-Dra_type=$(RA_TYPE) \
		-Dra_client_spid=$(RA_CLIENT_SPID) \
		-Dra_client_linkable=$(RA_CLIENT_LINKABLE) \
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
	$(RM) *.manifest *.manifest.sgx *.token *.sig OUTPUT* *.PID TEST_STDOUT TEST_STDERR

.PHONY: distclean
distclean: clean
	$(RM) -rf $(SRCDIR) $(PATCHED_GOLEVELDB) geth geth_init
