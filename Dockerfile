# Support setting various labels on the final image
ARG COMMIT=""
ARG VERSION=""
ARG BUILDNUM=""

# Pull Geth into a second stage deploy alpine container
FROM golang:1.18-bullseye as build-gramine

ARG GRAMINE_VERSION=gramine

RUN apt-get update && \
    apt-get install -y libssl-dev gnupg software-properties-common build-essential ca-certificates git

RUN apt-key adv --fetch-keys https://packages.gramineproject.io/gramine-keyring.gpg && \
    add-apt-repository 'deb [arch=amd64] https://packages.gramineproject.io/ stable main'

WORKDIR /geth-sgx
RUN apt-get update && apt-get install -y $GRAMINE_VERSION && \
    apt-get download $GRAMINE_VERSION libprotobuf-c1 openssl ca-certificates

ADD Makefile geth_init.cpp gramine-compatibility /geth-sgx/
ADD gramine-compatibility /geth-sgx/gramine-compatibility
RUN make geth

ARG ENCLAVE_SIZE="1024G"
ADD . /geth-sgx/
RUN gramine-sgx-gen-private-key && make ENCLAVE_SIZE=$ENCLAVE_SIZE SGX=1



# Pull Geth into a second stage deploy alpine container
FROM debian:bullseye

WORKDIR /geth-sgx
COPY --from=build-gramine /geth-sgx/*.manifest     \
                          /geth-sgx/*.manifest.sgx \
                          /geth-sgx/*.token        \
                          /geth-sgx/*.sig          \
                          /geth-sgx/geth           \
                          /geth-sgx/geth_init      \
                          ./
COPY --from=build-gramine /geth-sgx/*.deb /deb/
RUN dpkg --install --force-depends /deb/*.deb && rm -r /deb

EXPOSE 8545 8546 30303 30303/udp
ENTRYPOINT ["gramine-sgx", "/geth-sgx/geth"]

# Add some metadata labels to help programatic image consumption
ARG COMMIT=""
ARG VERSION=""
ARG BUILDNUM=""

LABEL commit="$COMMIT" version="$VERSION" buildnum="$BUILDNUM"

