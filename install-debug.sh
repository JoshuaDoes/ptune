#!/bin/bash

# Hide output from pushd/popd
pushd () {
    command pushd "$@" > /dev/null
}
popd () {
    command popd "$@" > /dev/null
}

echo "* Configuring the build environment"
export ZIP="ptune-dev.zip"
export SRCMOD="$PWD/module"

echo "* Packaging the module"
pushd "$SRCMOD" >&2
zip -r -0 -v "$ZIP" . > /dev/null
popd >&2
rm "$PWD/$ZIP" >/dev/null 2>&1
mv "$SRCMOD/$ZIP" "$PWD/$ZIP"

echo "* Installing the module"
echo ""
sudo magisk --install-module "$ZIP"
rm "$ZIP"

echo "* Setting the debug flag"
sudo touch /data/adb/modules_update/ptune/debug
