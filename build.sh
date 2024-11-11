#!/bin/bash

# Exit on error
set -e

# Hide output from pushd/popd
pushd () {
    command pushd "$@" > /dev/null
}
popd () {
    command popd "$@" > /dev/null
}

echo "* Configuring the build environment"
export VER="v1.1.2"
export ZIP="ptune-$VER.zip"
export SRCMOD="$PWD/module"

echo "* Packaging the module"
pushd "$SRCMOD" >&2
zip -r -0 -v "$ZIP" . > /dev/null
popd >&2
mv "$SRCMOD/$ZIP" "$PWD/$ZIP"

echo "* Done!"
echo "-> $ZIP"
