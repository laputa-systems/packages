.PHONY: test test-native xsh-native xsh-local-bins xsh-builder-image update-checksums

LAPUTA_DOCKER_PLATFORM ?= linux/arm64
XSH_TEST_IMAGE ?= laputa-packages-test
XSH_BUILD_IMAGE ?= xsh-test
XSH_ROOT ?= ../xsh
XSH ?= xsh
XSH_RELEASE ?= release-d09c6c3305ab8c650043bd8d32e03f2db6509e97
CARGO ?= $(shell command -v cargo 2>/dev/null || echo /home/josh/.cargo/bin/cargo)
PM_XSH_MODULE_PATH ?= .:/usr/lib/pm
PKGDIRS ?= $(sort $(patsubst %/PKGBUILD.xsh,%,$(wildcard repo/*/PKGBUILD.xsh)))
UPDATE_CHECKSUM_JOBS ?= 8
CHECKSUM_ROOT ?= .work/update-checksums/root
CHECKSUM_WORK ?= .work/update-checksums/work
CHECKSUM_OUT ?= .work/update-checksums/out

ifeq ($(LAPUTA_DOCKER_PLATFORM),linux/amd64)
XSH_LOCAL_TRIPLE ?= x86_64-unknown-linux-musl
XSH_RELEASE_ARCH ?= x86_64
XSH_RELEASE_XSH_SHA256 ?= 03e190c8ee15020b04b27e2066a7e53665452c9dce821bd0af80378ef664c746
XSH_RELEASE_XSHI_SHA256 ?= 897b22cae065625179f8b2cb18c48828464eb1cd135f32da0e9358b237f3e195
XSH_RELEASE_XSHT_SHA256 ?= 83ea617d6fc1a9f9e7908b292d51d8b263df15904d67d17b7c7f04d825a98a20
else
XSH_LOCAL_TRIPLE ?= aarch64-unknown-linux-musl
XSH_RELEASE_ARCH ?= aarch64
XSH_RELEASE_XSH_SHA256 ?= bc9117b8ac70c726002835e7ab1eaff0d45ede7b067bc85ddba7971eb8b8ffbb
XSH_RELEASE_XSHI_SHA256 ?= 5cf2f028fd0f0e6cbae213d7037e28e1aa92ca74768c5fce5e300d9725014bb6
XSH_RELEASE_XSHT_SHA256 ?= 86c2d1ac329702c0def779adb47640f84cdda9466630e2c98681750fc037a2e2
endif

XSH_ROOT_ABS := $(abspath $(XSH_ROOT))
XSH_LOCAL_BIN_DIR ?= $(XSH_ROOT)/target/$(XSH_LOCAL_TRIPLE)/debug
XSH_LOCAL_BINS := $(XSH_LOCAL_BIN_DIR)/xsh $(XSH_LOCAL_BIN_DIR)/xshi $(XSH_LOCAL_BIN_DIR)/xsht
XSH_NATIVE_BIN_DIR ?= $(XSH_ROOT)/target/debug

test-native: xsh-native
	PATH="$(abspath $(XSH_NATIVE_BIN_DIR)):$$PATH" \
	XSH_HOST="$(abspath $(XSH_NATIVE_BIN_DIR)/xsh)" \
	XSH_MODULE_PATH="$(CURDIR)" \
	XSH_PM_BUILD_CHROOT=0 \
	"$(abspath $(XSH_NATIVE_BIN_DIR)/xsht)" test --cov --cov-json target/coverage/pm-native.json tests/xsh/pm.xsh

xsh-native:
	$(CARGO) build --manifest-path "$(XSH_ROOT_ABS)/Cargo.toml" --bin xsh --bin xshi --bin xsht

test:
	docker build \
	    --platform $(LAPUTA_DOCKER_PLATFORM) \
	    --build-arg XSH_RELEASE=$(XSH_RELEASE) \
	    --build-arg XSH_RELEASE_ARCH=$(XSH_RELEASE_ARCH) \
	    --build-arg XSH_RELEASE_XSH_SHA256=$(XSH_RELEASE_XSH_SHA256) \
	    --build-arg XSH_RELEASE_XSHI_SHA256=$(XSH_RELEASE_XSHI_SHA256) \
	    --build-arg XSH_RELEASE_XSHT_SHA256=$(XSH_RELEASE_XSHT_SHA256) \
	    -t $(XSH_TEST_IMAGE) \
	    -f Dockerfile.test \
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
	    sh -c 'cargo build --target $(XSH_LOCAL_TRIPLE) --no-default-features --features "native-tests tools" --bin xsh --bin xshi --bin xsht'

xsh-builder-image:
	docker image inspect $(XSH_BUILD_IMAGE) >/dev/null 2>&1 || \
	    docker build --platform $(LAPUTA_DOCKER_PLATFORM) -t $(XSH_BUILD_IMAGE) -f "$(XSH_ROOT)/Dockerfile.test" "$(XSH_ROOT)"

update-checksums:
	@mkdir -p $(CHECKSUM_ROOT) $(CHECKSUM_WORK) $(CHECKSUM_OUT)
	@printf '%s\n' $(PKGDIRS) | xargs -n 1 -P $(UPDATE_CHECKSUM_JOBS) sh -c 'pkg="$$1"; name="$${pkg#repo/}"; XSH_MODULE_PATH="$(PM_XSH_MODULE_PATH)" $(XSH) pm.xsh -- update-checksums "$(CHECKSUM_ROOT)/$$name" "$(CHECKSUM_WORK)/$$name" "$(CHECKSUM_OUT)/$$name" "$$pkg"' sh
