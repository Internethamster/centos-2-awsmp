# All supported targets honor the `SRCDIR` variable to find the source-tree.
# For most unsupported targets, you are expected to have the source-tree as
# your working directory. To specify a different source-tree, simply override
# the variable via `SRCDIR=<path>` on the commandline. By default, the working
# directory is used for build output, but `BUILDDIR=<path>` allows overriding
# it.

BUILDDIR ?= .
SRCDIR ?= .
RST2MAN ?= rst2man
VERSION $= "1"


$(BUILDDIR)/:
	mkdir -p "$@"

$(BUILDDIR)/%/:
	mkdir -p "$@"


.PHONY: build
build:
	@/usr/bin/env python3 image-builder-8-stream.py -v $(VERSION)


