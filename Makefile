.PHONY: test

LAPUTA_DOCKER_PLATFORM ?= linux/arm64
XSH_RELEASE ?= release-e12de8c8ce6388bcbf80df96bf57ebd8afc2d0df
XSH_TEST_IMAGE ?= laputa-packages-test

ifeq ($(LAPUTA_DOCKER_PLATFORM),linux/amd64)
XSH_RELEASE_ARCH ?= x86_64
XSH_LOCAL_TRIPLE ?= x86_64-unknown-linux-musl
XSH_RELEASE_SHA256 ?= a000d143c13ecd83041e2e7c91690a09a4bc1d2405d859195082f07f85ac21ea
else
XSH_RELEASE_ARCH ?= aarch64
XSH_LOCAL_TRIPLE ?= aarch64-unknown-linux-musl
XSH_RELEASE_SHA256 ?= 0874226398877b375ce2a8453f7b587d75ec6a40a601fddcf33fd80dbdf08a27
endif

XSH_LOCAL_BIN_DIR ?= ../xsh/target/$(XSH_LOCAL_TRIPLE)/debug
XSH_LOCAL_BINS := $(XSH_LOCAL_BIN_DIR)/xsh $(XSH_LOCAL_BIN_DIR)/xsht

test:
ifeq ($(wildcard $(XSH_LOCAL_BINS)),$(XSH_LOCAL_BINS))
	docker build \
	    --platform $(LAPUTA_DOCKER_PLATFORM) \
	    --build-context xshbin=$(XSH_LOCAL_BIN_DIR) \
	    -t $(XSH_TEST_IMAGE) \
	    -f Dockerfile.test-local \
	    .
else
	docker build \
	    --platform $(LAPUTA_DOCKER_PLATFORM) \
	    --build-arg XSH_RELEASE=$(XSH_RELEASE) \
	    --build-arg XSH_RELEASE_ARCH=$(XSH_RELEASE_ARCH) \
	    --build-arg XSH_RELEASE_SHA256=$(XSH_RELEASE_SHA256) \
	    -t $(XSH_TEST_IMAGE) \
	    -f Dockerfile.test \
	    .
endif
	docker run --rm \
	    --platform $(LAPUTA_DOCKER_PLATFORM) \
	    -v "$(CURDIR)":/src/packages \
	    $(XSH_TEST_IMAGE)
