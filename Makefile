VERSION=${shell sh -c 'cat .version 2> /dev/null || git --git-dir git/fury/.git describe --exact-match --tags 2> /dev/null || git --git-dir git/fury/.git rev-parse --short HEAD'}
MKFILE := $(abspath $(lastword $(MAKEFILE_LIST)))/
ROOTDIR := $(dirname $MKFILE)

BLOOP_VERSION=1.2.5

deps=kaleidoscope totalitarian mitigation optometry eucalyptus exoskeleton escritoire mercator magnolia gastronomy contextual guillotine

NAILGUNJAR=nailgun-server-1.0.0.jar

all: clean-dist dist/bundle/bin/fury

publish: dist/install.sh
	gsutil -h "Cache-Control:public,max-age=60" cp $< gs://revivalist/downloads/fury.build/fury-$(VERSION).sh
	@echo
	@echo
	@echo "To install this version of Fury, run:"
	@echo
	@echo "  curl -OL https://storage.googleapis.com/revivalist/downloads/fury.build/fury-$(VERSION).sh"
	@echo "  sh install-$(VERSION).sh"
	@echo

dist/install.sh: dist/fury-$(VERSION).tar.gz dist/bundle/etc
	echo "#!/usr/bin/env sh" > dist/install.sh
	echo "FURY_VERSION=$(VERSION)" >> dist/install.sh
	cat etc/install.sh $< >> dist/install.sh
	chmod +x dist/install.sh

dist/fury-$(VERSION).tar.gz: dist/bundle/bin/fury dist/bundle/etc
	tar czvf $@ -C dist/bundle .

dist/bundle/etc:	#TODO refactor etc structure (separate bundled scripts from development ones)
	mkdir -p $@
	cp -r etc/aliases etc/bashrc etc/fishrc etc/zshrc etc/completion $@

######################## 
###    compilation   ###
########################
compile: bootstrap/bin/fury/.version

clean-compile: bloop-clean compile

watch: compile
	bloop compile fury --watch

bloop-clean:
	bloop clean fury

bootstrap/scala:
	mkdir -p $@
	curl https://downloads.lightbend.com/scala/2.12.8/scala-2.12.8.tgz | tar xvz -C $@ --strip 1

bootstrap/git/%:
	mkdir -p $@
	git clone https://github.com/propensive/$*.git $@ --branch=fury

bootstrap/bin:
	mkdir -p $@

bootstrap/bin/fury/.version: dist/bundle/bin/launcher bootstrap/scala dist/bundle/lib/$(NAILGUNJAR) $(foreach dep, $(deps), bootstrap/git/$(dep))
	$< --skip-bsp-connection $(BLOOP_VERSION)
	bloop compile fury
	echo "$(VERSION)" > $@

######################## 
###     libraries    ###
########################
dist/bundle/lib:
	mkdir -p $@

dist/bundle/lib/fury.jar: bootstrap/bin bootstrap/bin/fury/.version dist/bundle/lib $(foreach dep, $(deps), dist/bundle/lib/$(dep).jar)
	jar -cf $@ -C $< fury

dist/bundle/lib/$(NAILGUNJAR): dist/bundle/lib
	curl -o $@ http://central.maven.org/maven2/com/facebook/nailgun-server/1.0.0/nailgun-server-1.0.0.jar

dist/bundle/lib/%.jar: bootstrap/bin bootstrap/bin/fury/.version dist/bundle/lib
	jar -cf $@ -C $< $*


######################## 
###     binaries     ###
########################
binary-deps=coursier launcher ng

dist/bundle/bin:
	mkdir -p $@

dist/bundle/bin/fury: dist/bundle/lib/fury.jar $(foreach dep, $(binary-deps), dist/bundle/bin/$(dep))
	cp etc/fury $@
	chmod +x $@

dist/bundle/bin/coursier: dist/bundle/bin
	curl -s -L -o $@ https://git.io/coursier
	chmod +x $@

dist/bundle/bin/launcher: dist/bundle/bin/coursier
	$< bootstrap --quiet -f --deterministic --output $@ ch.epfl.scala:bloop-launcher_2.12:$(BLOOP_VERSION)

dist/bundle/bin/ng: dist/bundle/bin
	curl -s -L -o $@ https://raw.githubusercontent.com/facebook/nailgun/master/nailgun-client/py/ng.py
	sed -i '1 s/$$/2/' $@
	chmod +x $@

######################## 
###   verification   ###
########################
DOCKER_TAG=fury-ci

test-cases=ogdl
test-targets=$(foreach dep, $(test-cases), $(dep)-test)
.PHONY: $(test-targets)

$(test-targets): %-test: dist/bundle/bin/launcher bootstrap/bin/probably
	$< --skip-bsp-connection $(BLOOP_VERSION)
	bloop compile fury/$*-test
	bloop run fury/$*-test

bootstrap/bin/probably: dist/bundle/bin/launcher bootstrap/git/probably
	$< --skip-bsp-connection $(BLOOP_VERSION)
	bloop compile probably/cli

test:  bootstrap/bin/fury/.version $(test-targets)

integration:
	@echo "Not yet implemented"

test-isolated: ci
	@docker run -w /build -t $(DOCKER_TAG) make test

integration-isolated: ci
	@docker run -u bash_user -w /home/bash_user -t $(DOCKER_TAG) /test/run_all

ci:
	docker build -t $(DOCKER_TAG) .

clean-ci:
	docker build --no-cache -t fury-ci .

clean-dist:
	rm -rf dist

clean: clean-dist
	rm -rf bootstrap/bin/fury

.PHONY: all publish compile watch bloop-clean clean-compile clean-dist clean test ci clean-ci test-isolated integration-isolated integration
