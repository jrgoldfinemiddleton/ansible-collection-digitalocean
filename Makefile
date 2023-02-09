## MAKE VARIABLES ##

ANSIBLE_COLLECTION_VERSION ?= $(shell git describe --tags $$(git rev-parse --short HEAD))
ANSIBLE_COLLECTION_NAMESPACE ?= $(shell grep '^namespace:' galaxy.yml | awk '{ print $$2 }')
ANSIBLE_COLLECTION_NAME ?= $(shell grep '^name:' galaxy.yml | awk '{ print $$2 }')
ANSIBLE_COLLECTION_ARCHIVE_FILENAME ?= $(ANSIBLE_COLLECTION_NAMESPACE)-$(ANSIBLE_COLLECTION_NAME)-$(ANSIBLE_COLLECTION_VERSION).tar.gz

ANSIBLE_MOLECULE_SCENARIO ?=
ANSIBLE_MOLECULE_ROLE ?=

ANSIBLE_COLLECTIONS_PATH ?= /usr/share/ansible/collections
ANSIBLE_ROLES_PATH ?= roles
ANSIBLE_FORCE_COLOR := 1
PY_COLORS := 1

ANSIBLE_RUNNER_VERSION ?= stable-2.12-latest

DOCKER ?= docker
DOCKER_REGISTRY ?= docker.io
DOCKER_USERNAME ?= jrgoldfinemiddleton
DOCKER_IMAGE_EE_VERSION ?= $(shell git rev-parse --short HEAD)
DOCKER_IMAGE_EE_TAG_LATEST ?= latest
DOCKER_IMAGE_EE ?= $(DOCKER_REGISTRY)/jrgoldfinemiddleton/ansible-collection-$(ANSIBLE_COLLECTION_NAME)

DOCKER_CONFIG ?= .docker
DOCKER_MOUNT_SRC := /mnt/src
DOCKER_HOME ?= /tmp
DOCKER_BINDS := -v $(CURDIR):$(DOCKER_MOUNT_SRC)
DOCKER_ENV_ARGS := -e PYTHONPATH=. -e PY_COLORS=$(PY_COLORS) -e ANSIBLE_FORCE_COLOR=$(ANSIBLE_FORCE_COLOR)
DOCKER_USER :=

ifdef GITHUB_ACTIONS
	DOCKER_PULL ?= --pull always
else
	DOCKER_USER := --user=$(shell id -u):$(shell id -g)
	DOCKER_PULL ?= --pull missing
endif

DOCKER_RUN_BASE := $(DOCKER) run --rm --init $(DOCKER_PULL) $(DOCKER_ENV_ARGS) $(DOCKER_BINDS) -w $(DOCKER_MOUNT_SRC)
# Container user should have same uid/gid as host user to avoid creation of root-owned build artifacts on host system
DOCKER_RUN := $(DOCKER_RUN_BASE) $(DOCKER_USER) $(DOCKER_IMAGE_EE):$(DOCKER_IMAGE_EE_TAG_LATEST)
# Container user should be root to avoid failures gathering Ansible facts
DOCKER_RUN_MOLECULE := $(DOCKER_RUN_BASE) -e ANSIBLE_MOLECULE_GROUP -e DO_API_TOKEN $(DOCKER_IMAGE_EE):$(DOCKER_IMAGE_EE_TAG_LATEST)
DOCKER_RUN_INTERACTIVE := $(DOCKER_RUN_BASE) -it $(DOCKER_IMAGE_EE):$(DOCKER_IMAGE_EE_TAG_LATEST)


## MAKE TARGETS ##

# ANSIBLE EXECUTION ENVIRONMENT

.PHONY: login-docker
login-docker:
	$(DOCKER) --config $(DOCKER_CONFIG) login -u $(DOCKER_USERNAME) -p "$(DOCKER_PASSWORD)" $(DOCKER_REGISTRY)

.PHONY: build-docker-ansible-ee
build-docker-ansible-ee:
	$(DOCKER) build -f environment/Dockerfile --build-arg ANSIBLE_RUNNER_VERSION=$(ANSIBLE_RUNNER_VERSION) -t ansible-runner:$(ANSIBLE_COLLECTION_NAME)-latest environment
	$(DOCKER_RUN_BASE) $(DOCKER_USER) quay.io/ansible/ansible-builder ansible-builder create -f environment/execution-environment.yml -c environment/context
	$(DOCKER) build -f environment/context/Dockerfile -t $(DOCKER_IMAGE_EE):$(DOCKER_IMAGE_EE_VERSION) environment/context
	$(DOCKER) tag $(DOCKER_IMAGE_EE):$(DOCKER_IMAGE_EE_VERSION) $(DOCKER_IMAGE_EE):$(DOCKER_IMAGE_EE_TAG_LATEST)

.PHONY: push-docker-ansible-ee
push-docker-ansible-ee:
	$(DOCKER) --config $(DOCKER_CONFIG) push $(DOCKER_IMAGE_EE):$(DOCKER_IMAGE_EE_VERSION)
	$(DOCKER) --config $(DOCKER_CONFIG) push $(DOCKER_IMAGE_EE):$(DOCKER_IMAGE_EE_TAG_LATEST)

.PHONY: docker-ansible-ee
docker-ansible-ee:
	login-docker build-docker-ansible-ee push-docker-ansible-ee


# LINT

.PHONY: lint-yaml
lint-yaml:
	$(DOCKER_RUN) yamllint .

.PHONY: lint-ansible
lint-ansible:
	$(DOCKER_RUN) ansible-lint -v

.PHONY: lint
lint: lint-yaml lint-ansible


# MOLECULE

.PHONY: test
test:
	$(DOCKER_RUN_MOLECULE) bash -c 'cd $(ANSIBLE_ROLES_PATH)/$(ANSIBLE_MOLECULE_ROLE); molecule test -s $(ANSIBLE_MOLECULE_SCENARIO)'


# RELEASE

.PHONY: collection-build
collection-build:
	$(DOCKER_RUN) rm -rf dist && mkdir -p dist
	$(DOCKER_RUN) sed -i 's/version: 0.0.0/version: $(ANSIBLE_COLLECTION_VERSION)/' galaxy.yml
	$(DOCKER_RUN) ansible-galaxy collection build . --output-path dist
	$(DOCKER_RUN) sed -i 's/version: $(ANSIBLE_COLLECTION_VERSION)/version: 0.0.0/' galaxy.yml

.PHONY: collection-publish
collection-publish: collection-build
	$(DOCKER_RUN) ansible-galaxy collection publish dist/$(ANSIBLE_COLLECTION_ARCHIVE_FILENAME) --token $(ANSIBLE_GALAXY_TOKEN)
	rm -rf dist


# MISCELLANEOUS

.PHONY: run-playbook
run-playbook:
	$(DOCKER_RUN_INTERACTIVE) ansible-playbook $(ANSIBLE_PLAYBOOK) $(ANSIBLE_PLAYBOOK_EXTRA_ARGS)

.PHONY: run-bash
run-bash:
	$(DOCKER_RUN_INTERACTIVE) bash

.PHONY: clean
clean:
	$(DOCKER_RUN) rm -rf dist .cache environment/context .docker

#TODO: consider adding Ansible Runner or Ansible Navigator targets
