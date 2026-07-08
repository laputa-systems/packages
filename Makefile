.PHONY: test xsh-local-bins xsh-builder-image update-checksums

LAPUTA_DOCKER_PLATFORM ?= linux/arm64
XSH_TEST_IMAGE ?= laputa-packages-test
XSH_BUILD_IMAGE ?= xsh-test
XSH_ROOT ?= ../xsh
XSH ?= xsh
PM_XSH_MODULE_PATH ?= .:/usr/lib/pm
PKGDIRS ?= $(sort $(patsubst %/PKGBUILD.xsh,%,$(wildcard repo/*/PKGBUILD.xsh)))
UPDATE_CHECKSUM_JOBS ?= 8
CHECKSUM_ROOT ?= .work/update-checksums/root
CHECKSUM_WORK ?= .work/update-checksums/work
CHECKSUM_OUT ?= .work/update-checksums/out

ifeq ($(LAPUTA_DOCKER_PLATFORM),linux/amd64)
XSH_LOCAL_TRIPLE ?= x86_64-unknown-linux-musl
else
XSH_LOCAL_TRIPLE ?= aarch64-unknown-linux-musl
endif

XSH_ROOT_ABS := $(abspath $(XSH_ROOT))
XSH_LOCAL_BIN_DIR ?= $(XSH_ROOT)/target/$(XSH_LOCAL_TRIPLE)/debug
XSH_LOCAL_BINS := $(XSH_LOCAL_BIN_DIR)/xsh $(XSH_LOCAL_BIN_DIR)/xsht

test: xsh-local-bins
	docker build \
	    --platform $(LAPUTA_DOCKER_PLATFORM) \
	    --build-context xshbin=$(XSH_LOCAL_BIN_DIR) \
	    -t $(XSH_TEST_IMAGE) \
	    -f Dockerfile.test-local \
	    .
	docker run --rm \
	    --platform $(LAPUTA_DOCKER_PLATFORM) \
	    -v "$(CURDIR)":/src/packages \
	    $(XSH_TEST_IMAGE)

xsh-local-bins: xsh-builder-image
	docker run --rm \
	    --platform $(LAPUTA_DOCKER_PLATFORM) \
	    -v "$(XSH_ROOT_ABS)":/work \
	    -v "$(XSH_ROOT_ABS)/target/$(XSH_LOCAL_TRIPLE)":/work/target/$(XSH_LOCAL_TRIPLE) \
	    -w /work \
	    $(XSH_BUILD_IMAGE) \
	    sh -c 'cargo build --target $(XSH_LOCAL_TRIPLE) --no-default-features --features "native-tests tools" --bin xsh --bin xsht'

xsh-builder-image:
	docker image inspect $(XSH_BUILD_IMAGE) >/dev/null 2>&1 || \
	    docker build --platform $(LAPUTA_DOCKER_PLATFORM) -t $(XSH_BUILD_IMAGE) -f "$(XSH_ROOT)/Dockerfile.test" "$(XSH_ROOT)"

update-checksums:
	@mkdir -p $(CHECKSUM_ROOT) $(CHECKSUM_WORK) $(CHECKSUM_OUT)
	@printf '%s\n' $(PKGDIRS) | xargs -n 1 -P $(UPDATE_CHECKSUM_JOBS) sh -c 'pkg="$$1"; name="$${pkg#repo/}"; XSH_MODULE_PATH="$(PM_XSH_MODULE_PATH)" $(XSH) pm.xsh -- update-checksums "$(CHECKSUM_ROOT)/$$name" "$(CHECKSUM_WORK)/$$name" "$(CHECKSUM_OUT)/$$name" "$$pkg"' sh
