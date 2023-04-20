# Support setting various labels on the final image
ARG COMMIT=""
ARG VERSION=""
ARG BUILDNUM=""

# Build Geth into a first stage container
FROM golang:1.20-bullseye as build-gramine

RUN apt-get update && \
    apt-get install -y curl libssl-dev build-essential ca-certificates git

RUN curl -fsSLo /usr/share/keyrings/gramine-keyring.gpg https://packages.gramineproject.io/gramine-keyring.gpg && \
    echo 'deb [arch=amd64 signed-by=/usr/share/keyrings/gramine-keyring.gpg] https://packages.gramineproject.io/ focal main' > /etc/apt/sources.list.d/gramine.list

WORKDIR /geth-sgx
RUN apt-get update && apt-get install -y gramine

ADD Makefile geth_init.cpp geth-patches /geth-sgx/
ADD geth-patches /geth-sgx/geth-patches
RUN make PROTECT=1 TLS=1 geth

ARG MAINNET="0"
ARG SEPOLIA="0"
ARG ENCLAVE_SIZE="1024G"
ADD . /geth-sgx/
RUN gramine-sgx-gen-private-key && make ENCLAVE_SIZE=$ENCLAVE_SIZE MAINNET=$MAINNET SEPOLIA=$SEPOLIA SGX=1



# Pull Geth into a second stage deploy container
FROM debian:bullseye

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y curl && \
    curl -fsSLo /usr/share/keyrings/gramine-keyring.gpg https://packages.gramineproject.io/gramine-keyring.gpg && \
    echo 'deb [arch=amd64 signed-by=/usr/share/keyrings/gramine-keyring.gpg] https://packages.gramineproject.io/ focal main' > /etc/apt/sources.list.d/gramine.list && \
    curl -fsSLo /usr/share/keyrings/intel-sgx-deb.key https://download.01.org/intel-sgx/sgx_repo/ubuntu/intel-sgx-deb.key && \
    echo 'deb [arch=amd64 signed-by=/usr/share/keyrings/intel-sgx-deb.key] https://download.01.org/intel-sgx/sgx_repo/ubuntu focal main' > /etc/apt/sources.list.d/intel-sgx.list && \
    curl -fsSLo /usr/share/keyrings/microsoft.key https://packages.microsoft.com/keys/microsoft.asc && \
    echo 'deb [arch=amd64 signed-by=/usr/share/keyrings/microsoft.key] https://packages.microsoft.com/ubuntu/20.04/prod focal main' > /etc/apt/sources.list.d/microsoft.list && \
    apt-get update && \
    apt-get install -y libsgx-dcap-ql az-dcap-client && \
    apt-get download gramine gramine-ratls-dcap libprotobuf-c1 && \
    dpkg --install --force-depends *.deb && rm -r *.deb

WORKDIR /geth-sgx
COPY --from=build-gramine /geth-sgx/*.manifest     \
                          /geth-sgx/*.manifest.sgx \
                          /geth-sgx/*.token        \
                          /geth-sgx/*.sig          \
                          /geth-sgx/*.args         \
                          /geth-sgx/geth           \
                          /geth-sgx/geth_init      \
                          ./

EXPOSE 8545 8546 30303 30303/udp
ENTRYPOINT ["gramine-sgx", "/geth-sgx/geth"]

# Add some metadata labels to help programatic image consumption
ARG COMMIT=""
ARG VERSION=""
ARG BUILDNUM=""

LABEL commit="$COMMIT" version="$VERSION" buildnum="$BUILDNUM"

