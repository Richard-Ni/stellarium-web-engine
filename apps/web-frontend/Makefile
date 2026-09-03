# Stellarium Web - Copyright (c) 2019 - Noctua Software Ltd
#
# This program is licensed under the terms of the GNU AGPL v3, or
# alternatively under a commercial licence.
#
# The terms of the AGPL v3 license can be found in the main directory of this
# repository.

.PHONY: setup build build-local dev start preview

gen-es6:
	cd ../.. && docker run -it -p 8000:8000 -v "$(CURDIR)/../..:/app" swe-dev /bin/bash -c "source /emsdk/emsdk_env.sh && make js-es6"

gen-es6-debug:
	cd ../.. && docker run -it -p 8000:8000 -v "$(CURDIR)/../..:/app" swe-dev /bin/bash -c "source /emsdk/emsdk_env.sh && make js-es6-debug"

gen-es6-prof:
	cd ../.. && docker run -it -p 8000:8000 -v "$(CURDIR)/../..:/app"  swe-dev /bin/bash -c "source /emsdk/emsdk_env.sh && make js-es6-prof"

update-engine:
	make gen-es6
	cp ../../build/stellarium-web-engine.js src/assets/js/
	cp ../../build/stellarium-web-engine.wasm src/assets/js/

update-engine-debug:
	make gen-es6-debug
	cp ../../build/stellarium-web-engine.js src/assets/js/
	cp ../../build/stellarium-web-engine.wasm src/assets/js/

USER_UID := $(shell id -u)
USER_GID := $(shell id -g)

DOCKER_MOUNTS := -v "$(CURDIR):/app" -v "$(CURDIR)/../test-skydata:/skydata" $(EXTRA_DOCKER_MOUNTS)

setup: Dockerfile Dockerfile.jsbuild
	# Build docker image for compilation with emscripten
	docker build -f Dockerfile.jsbuild -t swe-dev . # --no-cache
	make update-engine
	# Build docker image for webpack/node development
	docker build -t stellarium-web-dev --build-arg USER_UID=${USER_UID} --build-arg USER_GID=${USER_GID} .
	docker run -it $(DOCKER_MOUNTS) stellarium-web-dev yarn install

dev:
	docker run -it -p 8080:8080 -p 8888:8888 $(DOCKER_MOUNTS) stellarium-web-dev yarn run dev

lint:
	docker run -it -p 8080:8080 -p 8888:8888 $(DOCKER_MOUNTS) stellarium-web-dev yarn run lint

# Build inside docker. Requires `make setup` first, to get the
# stellarium-web-dev image.
build:
	docker run -it $(DOCKER_MOUNTS) stellarium-web-dev yarn run build

# Build on the host, without docker. Requires yarn install to have been run
# once. NODE_OPTIONS is needed because webpack 4 uses a hash algorithm that
# OpenSSL 3 (node >= 17) refuses; the docker image avoids it by pinning node 12.
# Set CDN_ENV to deploy under a subpath, eg: make build-local CDN_ENV=/swe/
build-local:
	NODE_OPTIONS=--openssl-legacy-provider yarn build

start:
	cd dist && python3 -m http.server 8080

# Preview the built dist/ locally.  Unlike start, deep links of the history
# mode router keep working on a reload.  Override the port with PORT=8081.
preview:
	python3 ./tools/preview.py --port $(or $(PORT),8080)

i18n:
	python3 ./tools/update-i18n-en.py
