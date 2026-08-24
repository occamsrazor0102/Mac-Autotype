.PHONY: build test run install release clean

REPO_ROOT := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))

build:
	"$(REPO_ROOT)/build.sh"

test:
	"$(REPO_ROOT)/scripts/test.sh"

run:
	"$(REPO_ROOT)/run.sh"

install:
	"$(REPO_ROOT)/install.sh"

release:
	"$(REPO_ROOT)/scripts/release.sh" --adhoc

clean:
	swift package --package-path "$(REPO_ROOT)" clean
	rm -rf -- "$(REPO_ROOT)/dist"
