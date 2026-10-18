GO      ?= go
BIN     := dm-lite
DIST    := dist

.PHONY: all check vet fmt build cross windows clean apk

all: cross windows

check: vet build

vet:
	$(GO) vet ./...

fmt:
	@out=$$(gofmt -l $$(find . -name '*.go' -not -path './vendor/*')); if [ -n "$$out" ]; then echo "gofmt pendiente:"; echo "$$out"; exit 1; fi

build:
	$(GO) build -o $(BIN) ./agent

cross:
	@mkdir -p $(DIST)
	CGO_ENABLED=0 GOOS=linux GOARCH=amd64 $(GO) build -o $(DIST)/$(BIN)-linux-amd64 ./agent
	CGO_ENABLED=0 GOOS=linux GOARCH=arm64 $(GO) build -o $(DIST)/$(BIN)-linux-arm64 ./agent
	CGO_ENABLED=0 GOOS=linux GOARCH=arm GOARM=7 $(GO) build -o $(DIST)/$(BIN)-linux-arm7 ./agent

windows:
	@mkdir -p $(DIST)
	CGO_ENABLED=0 GOOS=windows GOARCH=amd64 $(GO) build -o $(DIST)/$(BIN)-windows-amd64.exe ./agent
	CGO_ENABLED=0 GOOS=windows GOARCH=arm64 $(GO) build -o $(DIST)/$(BIN)-windows-arm64.exe ./agent

apk:
	bash app/build-apk.sh

clean:
	rm -rf $(DIST) $(BIN) $(BIN).exe app/build
