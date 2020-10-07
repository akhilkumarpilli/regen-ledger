PACKAGES_SIMTEST=$(shell go list ./... | grep '/simulation')
VERSION := $(shell echo $(shell git describe --tags) | sed 's/^v//')
COMMIT := $(shell git log -1 --format='%H')
LEDGER_ENABLED ?= true

export GO111MODULE = on

# process build tags

build_tags = netgo
ifeq ($(LEDGER_ENABLED),true)
  ifeq ($(OS),Windows_NT)
    GCCEXE = $(shell where gcc.exe 2> NUL)
    ifeq ($(GCCEXE),)
      $(error gcc.exe not installed for ledger support, please install or set LEDGER_ENABLED=false)
    else
      build_tags += ledger
    endif
  else
    UNAME_S = $(shell uname -s)
    ifeq ($(UNAME_S),OpenBSD)
      $(warning OpenBSD detected, disabling ledger support (https://github.com/cosmos/cosmos-sdk/issues/1988))
    else
      GCC = $(shell command -v gcc 2> /dev/null)
      ifeq ($(GCC),)
        $(error gcc not installed for ledger support, please install or set LEDGER_ENABLED=false)
      else
        build_tags += ledger
      endif
    endif
  endif
endif

ifeq ($(WITH_CLEVELDB),yes)
  build_tags += gcc
endif
build_tags += $(BUILD_TAGS)
build_tags := $(strip $(build_tags))

whitespace :=
whitespace += $(whitespace)
comma := ,
build_tags_comma_sep := $(subst $(whitespace),$(comma),$(build_tags))

# process linker flags

ldflags = -X github.com/cosmos/cosmos-sdk/version.Name=xrn \
		  -X github.com/cosmos/cosmos-sdk/version.ServerName=xrnd \
		  -X github.com/cosmos/cosmos-sdk/version.ClientName=xrncli \
		  -X github.com/cosmos/cosmos-sdk/version.Version=$(VERSION) \
		  -X github.com/cosmos/cosmos-sdk/version.Commit=$(COMMIT) \
		  -X "github.com/cosmos/cosmos-sdk/version.BuildTags=$(build_tags_comma_sep)"

ifeq ($(WITH_CLEVELDB),yes)
  ldflags += -X github.com/cosmos/cosmos-sdk/types.DBBackend=cleveldb
endif
ldflags += $(LDFLAGS)
ldflags := $(strip $(ldflags))

BUILD_FLAGS := -tags "$(build_tags)" -ldflags '$(ldflags)'

# The below include contains the tools target.
include contrib/devtools/Makefile

all: install lint check

build: go.sum
ifeq ($(OS),Windows_NT)
	go build -mod=readonly $(BUILD_FLAGS) -o build/xrnd.exe ./cmd/xrnd
	go build -mod=readonly $(BUILD_FLAGS) -o build/xrncli.exe ./cmd/xrncli
else
	go build $(BUILD_FLAGS) -o build/xrnd ./cmd/xrnd
	go build $(BUILD_FLAGS) -o build/xrncli ./cmd/xrncli
endif

build-linux: go.sum
	LEDGER_ENABLED=false GOOS=linux GOARCH=amd64 $(MAKE) build

install: go.sum check-ledger
	go install -mod=readonly $(BUILD_FLAGS) ./cmd/xrnd
	go install -mod=readonly $(BUILD_FLAGS) ./cmd/xrncli

install-debug: go.sum
	go install -mod=readonly $(BUILD_FLAGS) ./cmd/xrndebug


########################################
### Tools & dependencies

go-mod-cache: go.sum
	@echo "--> Download go modules to local cache"
	@go mod download

go.sum: go.mod
	@echo "--> Ensure dependencies have not been modified"
	@go mod verify

draw-deps:
	@# requires brew install graphviz or apt-get install graphviz
	go get github.com/RobotsAndPencils/goviz
	@goviz -i ./cmd/xrnd -d 2 | dot -Tpng -o dependency-graph.png

clean:
	rm -rf snapcraft-local.yaml build/

distclean: clean
	rm -rf vendor/

########################################
### Testing


check: check-unit check-build
check-all: check check-race check-cover

check-unit:
	@VERSION=$(VERSION) go test -mod=readonly -tags='ledger test_ledger_mock' ./...

check-race:
	@VERSION=$(VERSION) go test -mod=readonly -race -tags='ledger test_ledger_mock' ./...

check-cover:
	@go test -mod=readonly -timeout 30m -race -coverprofile=coverage.txt -covermode=atomic -tags='ledger test_ledger_mock' ./...

check-build: build
	@go test -mod=readonly -p 4 `go list ./cli_test/...` -tags=cli_test


lint: ci-lint
ci-lint:
	golangci-lint run
	find . -name '*.go' -type f -not -path "./vendor*" -not -path "*.git*" | xargs gofmt -d -s
	go mod verify

format:
	find . -name '*.go' -type f -not -path "./vendor*" -not -path "*.git*" -not -path "./client/lcd/statik/statik.go" | xargs gofmt -w -s
	find . -name '*.go' -type f -not -path "./vendor*" -not -path "*.git*" -not -path "./client/lcd/statik/statik.go" | xargs misspell -w
	find . -name '*.go' -type f -not -path "./vendor*" -not -path "*.git*" -not -path "./client/lcd/statik/statik.go" | xargs goimports -w -local github.com/cosmos/cosmos-sdk

benchmark:
	@go test -mod=readonly -bench=. ./...


########################################
### Local validator nodes using docker and docker-compose

build-docker-xrndnode:
	$(MAKE) -C networks/local

# Run a 4-node testnet locally
localnet-start: localnet-stop
	@if ! [ -f build/node0/xrnd/config/genesis.json ]; then docker run --rm -v $(CURDIR)/build:/xrnd:Z tendermint/xrndnode testnet --v 4 -o . --starting-ip-address 192.168.10.2 ; fi
	docker-compose up -d

# Stop testnet
localnet-stop:
	docker-compose down

# include simulations
include sims.mk

.PHONY: all build-linux install install-debug \
	go-mod-cache draw-deps clean \
	check check-all check-build check-cover check-ledger check-unit check-race

test:
	go test ./...

test_cover:
	bash -x tests/test_cover.sh
