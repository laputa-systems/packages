.PHONY: test

LAPUTA_DOCKER_PLATFORM ?= linux/arm64
XSH_RELEASE ?= release-dbeacac33697faa06b47633108d144297f54f798
XSH_TEST_IMAGE ?= laputa-packages-test

ifeq ($(LAPUTA_DOCKER_PLATFORM),linux/amd64)
XSH_RELEASE_ARCH ?= x86_64
XSH_RELEASE_SHA256 ?= dc958ada6a5418c197eb2aae2a95a9a63299382fc994611f41b38903c19d1761
else
XSH_RELEASE_ARCH ?= aarch64
XSH_RELEASE_SHA256 ?= f7afb27dc8cb340b8dedf332f649fd58cc2f15c7617cd4a67b19677b1fdedaa7
endif

test:
	docker build \
	    --platform $(LAPUTA_DOCKER_PLATFORM) \
	    --build-arg XSH_RELEASE=$(XSH_RELEASE) \
	    --build-arg XSH_RELEASE_ARCH=$(XSH_RELEASE_ARCH) \
	    --build-arg XSH_RELEASE_SHA256=$(XSH_RELEASE_SHA256) \
	    -t $(XSH_TEST_IMAGE) \
	    -f Dockerfile.test \
	    .
	docker run --rm \
	    --platform $(LAPUTA_DOCKER_PLATFORM) \
	    -v "$(CURDIR)":/src/packages \
	    $(XSH_TEST_IMAGE)
