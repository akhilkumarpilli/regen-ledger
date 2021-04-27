FROM golang:1.15-buster AS build-env

# Install minimum necessary dependencies,
ENV PACKAGES curl make git libc-dev bash gcc python3 ca-certificates
RUN apt-get update && apt-get install --no-install-recommends -y $PACKAGES && \
    rm -rf /var/lib/apt/lists/* && apt-get clean

# Set working directory for the build
WORKDIR /go/src/github.com/regen-network/regen-ledger

# Add source files
COPY . .

# install regen, remove packages
RUN make install

WORKDIR /root

EXPOSE 26656 26657 1317 9090

# Run regen by default, omit entrypoint to ease using container with regen
CMD ["regen"]