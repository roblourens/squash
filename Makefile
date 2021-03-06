.PHONY: all
all: binaries deployment

.PHONY: binaries
binaries: target/squash-server/squash-server target/squash-client/squash-client target/squash

.PHONY: release-binaries
release-binaries: target/squash-server/squash-server target/squash-client/squash-client target/squash-linux target/squash-osx

.PHONY: containers
containers: target/squash-server-container target/squash-client-container

.PHONY: prep-containers
prep-containers: ./target/squash-server/squash-server target/squash-server/Dockerfile target/squash-client/squash-client target/squash-client/Dockerfile

DOCKER_REPO ?= soloio
VERSION ?= $(shell git describe --tags)


SRCS=$(shell find ./pkg -name "*.go") $(shell find ./cmd -name "*.go")

target:
	[ -d $@ ] || mkdir -p $@

target/squash: target $(SRCS)
	go build -o $@ ./cmd/squash-cli

target/squash-linux: target $(SRCS)
	GOOS=linux go build -o $@ ./cmd/squash-cli

target/squash-osx: target $(SRCS)
	GOOS=darwin go build -o $@ ./cmd/squash-cli

target/squash-client/: | target
target/squash-client/:
	[ -d $@ ] || mkdir -p $@

target/squash-client/squash-client: | target/squash-client/
target/squash-client/squash-client: $(SRCS)
	GOOS=linux CGO_ENABLED=0 go build -ldflags '-w' -o target/squash-client/squash-client ./cmd/squash-client/platforms/kubernetes

target/squash-client/Dockerfile: | target/squash-client/

target/squash-client/Dockerfile: ./cmd/squash-client/platforms/kubernetes/Dockerfile
	cp -f ./cmd/squash-client/platforms/kubernetes/Dockerfile ./target/squash-client/Dockerfile

target/squash-server/:
	[ -d $@ ] || mkdir -p $@

target/squash-server/squash-server: | target/squash-server/
target/squash-server/Dockerfile:    | target/squash-server/

target/squash-server/squash-server: $(SRCS)
	GOOS=linux CGO_ENABLED=0  go build -ldflags '-w' -o ./target/squash-server/squash-server ./cmd/squash-server/

target/squash-server/Dockerfile: cmd/squash-server/Dockerfile
	cp cmd/squash-server/Dockerfile target/squash-server/Dockerfile


target/squash-server-container: ./target/squash-server/squash-server target/squash-server/Dockerfile
	docker build -t $(DOCKER_REPO)/squash-server:$(VERSION) ./target/squash-server/
	touch $@

target/squash-client-container: target/squash-client/squash-client target/squash-client/Dockerfile
	docker build -t $(DOCKER_REPO)/squash-client:$(VERSION) ./target/squash-client/
	touch $@

target/squash-client-base-container:
	docker build -t $(DOCKER_REPO)/squash-client-base -f cmd/squash-client/platforms/kubernetes/Dockerfile.base cmd/squash-client/platforms/kubernetes/
	touch $@

.PHONY: push-client-base
push-client-base:
	docker push $(DOCKER_REPO)/squash-client-base

target/%.yml : contrib/%.yml.tmpl
	SQUASH_REPO=$(DOCKER_REPO) SQUASH_VERSION=$(VERSION) go run contrib/templategen.go $< > $@

target/kubernetes/squash-server.yml: target/squash-server-container
target/kubernetes/squash-client.yml: target/squash-client-container

target/kubernetes/:
	[ -d $@ ] || mkdir -p $@

deployment: | target/kubernetes/
deployment: target/kubernetes/squash-client.yml target/kubernetes/squash-server.yml


.PHONY: clean
clean:
	rm -rf target

pkg/restapi: api.yaml
	swagger generate server --name=Squash --exclude-main --target=./pkg/  --spec=./api.yaml
	swagger generate client --name=Squash --target=./pkg/  --spec=./api.yaml

dist: target/squash-server-container target/squash-client-container
	docker push $(DOCKER_REPO)/squash-client:$(VERSION)
	docker push $(DOCKER_REPO)/squash-server:$(VERSION)