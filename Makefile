#!/usr/bin/make -f

SHELL := /bin/bash
IMG_NAME := wireguard
IMG_REPO := nforceroh
IMG_NS := torrent
IMG_REG := default-route-openshift-image-registry.apps.ocp.nf.lab
DATE_VERSION := $(shell date +"v%Y%m%d%H%M" )
BRANCH := $(shell git rev-parse --abbrev-ref HEAD)
DOCKERCMD := docker
COMMIT_MSG ?= Update
HEALTHCHECK_TIMEOUT ?= 90
HEALTHCHECK_INTERVAL ?= 3
WG_CONFIG_FILE ?= /etc/wireguard/wg0.conf

ifeq ($(BRANCH),dev)
	VERSION := dev
else
	VERSION := $(BRANCH)
endif

#oc get route default-route -n openshift-image-registry
#podman login -u sylvain -p $(oc whoami -t) default-route-openshift-image-registry.apps.ocp.nf.lab

.PHONY: all build push gitcommit gitpush create smoke healthcheck healthcheck-live
all: build push 
git: gitcommit gitpush 

build: 
	@echo "Building $(IMG_NAME)image"
	$(DOCKERCMD) build \
		--build-arg BUILD_DATE="$(BUILD_DATE)" \
		--build-arg VCS_REF="$(VERSION)" \
		--build-arg VERSION="$(VERSION)" \
		--tag $(IMG_REPO)/$(IMG_NAME) .

smoke:
	@echo "Running smoke tests"
	bash -n content/usr/local/bin/entrypoint.sh
	python3 -m py_compile content/usr/local/bin/wg_healthcheck.py
	$(MAKE) healthcheck

healthcheck:
	@echo "Validating healthcheck endpoint"
	@set -e; \
	python3 content/usr/local/bin/wg_healthcheck.py >/tmp/wg_healthcheck.log 2>&1 & \
	pid=$$!; \
	trap 'kill $$pid >/dev/null 2>&1 || true; wait $$pid >/dev/null 2>&1 || true' EXIT; \
	sleep 1; \
	status=503; \
	if python3 -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8080', timeout=3)" >/dev/null 2>&1; then status=200; fi; \
	if [[ "$$status" != "503" ]]; then \
		echo "Unexpected healthcheck status: $$status (expected 503 without wg0)"; \
		exit 1; \
	fi; \
	echo "Healthcheck endpoint responded with expected status $$status"

healthcheck-live: build
	@echo "Running live container healthcheck (expects HTTP 200 via Docker HEALTHCHECK)"
	@test -f "$(WG_CONFIG_FILE)" || (echo "WG config file not found: $(WG_CONFIG_FILE)" && exit 1)
	@set -e; \
	name="wg-live-hc-$$RANDOM"; \
	cid=""; \
	cleanup() { \
		if [[ -n "$$cid" ]]; then \
			$(DOCKERCMD) logs "$$cid" >/tmp/$$name.log 2>&1 || true; \
			$(DOCKERCMD) rm -f "$$cid" >/dev/null 2>&1 || true; \
		fi; \
	}; \
	trap cleanup EXIT; \
	cid=$$($(DOCKERCMD) run -d --rm \
		--name "$$name" \
		--cap-add=NET_ADMIN \
		--cap-add=SYS_MODULE \
		--device /dev/net/tun \
		-v "$(WG_CONFIG_FILE)":/etc/wireguard/wg0.conf:ro \
		"$(IMG_REPO)/$(IMG_NAME)"); \
	echo "Started container $$cid"; \
	elapsed=0; \
	while (( elapsed < $(HEALTHCHECK_TIMEOUT) )); do \
		state=$$($(DOCKERCMD) inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$$cid" 2>/dev/null || echo exited); \
		if [[ "$$state" == "healthy" ]]; then \
			echo "Container reported healthy"; \
			exit 0; \
		fi; \
		if [[ "$$state" == "unhealthy" || "$$state" == "exited" ]]; then \
			echo "Container reported $$state"; \
			$(DOCKERCMD) logs "$$cid" || true; \
			exit 1; \
		fi; \
		sleep $(HEALTHCHECK_INTERVAL); \
		elapsed=$$((elapsed + $(HEALTHCHECK_INTERVAL))); \
	done; \
	echo "Timed out waiting for healthy status after $(HEALTHCHECK_TIMEOUT)s"; \
	$(DOCKERCMD) logs "$$cid" || true; \
	exit 1

gitcommit:
	git commit -m "$(COMMIT_MSG)"

gitpush:
	@echo "Building $(IMG_NAME):$(VERSION) image"
	git tag -a $(VERSION) -m "Update to $(VERSION)"
	git push --tags

push: 
	@echo "Tagging and Pushing $(IMG_NAME):$(VERSION) image"
ifeq ($(VERSION), dev)
	$(DOCKERCMD) tag $(IMG_REPO)/$(IMG_NAME) docker.io/$(IMG_REPO)/$(IMG_NAME):dev
	$(DOCKERCMD) push docker.io/$(IMG_REPO)/$(IMG_NAME):dev
else
#	$(DOCKERCMD) tag $(IMG_REPO)/$(IMG_NAME) docker.io/$(IMG_REPO)/$(IMG_NAME):$(DATE_VERSION)
#	$(DOCKERCMD) tag $(IMG_REPO)/$(IMG_NAME) docker.io/$(IMG_REPO)/$(IMG_NAME):latest
	$(DOCKERCMD) tag $(IMG_REPO)/$(IMG_NAME) $(IMG_REG)/$(IMG_NS)/$(IMG_NAME):$(DATE_VERSION)
	$(DOCKERCMD) tag $(IMG_REPO)/$(IMG_NAME) $(IMG_REG)/$(IMG_NS)/$(IMG_NAME):latest
	$(DOCKERCMD) push $(IMG_REG)/$(IMG_NS)/$(IMG_NAME):$(DATE_VERSION)
	$(DOCKERCMD) push $(IMG_REG)/$(IMG_NS)/$(IMG_NAME):latest
#	$(DOCKERCMD) push docker.io/$(IMG_REPO)/$(IMG_NAME):$(DATE_VERSION)
#	$(DOCKERCMD) push docker.io/$(IMG_REPO)/$(IMG_NAME):latest
endif

end:
	@echo "Done!"