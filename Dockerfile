FROM ubuntu:18.04 AS build-env

# Install minimum necessary dependencies,
RUN apt-get update -y && apt-get install -y build-essential git wget && apt-get clean
RUN cd /tmp && \
    wget https://dl.google.com/go/go1.15.linux-amd64.tar.gz && \
    tar -xvf go1.15.linux-amd64.tar.gz && \
    rm go1.15.linux-amd64.tar.gz && \
    mv go /usr/local

ENV GOROOT /usr/local/go
ENV GOPATH $HOME/go
ENV PATH $GOPATH/bin:$GOROOT/bin:$PATH

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