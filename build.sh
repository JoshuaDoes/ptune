#!/bin/bash

# Hide output from pushd/popd
pushd () {
    command pushd "$@" > /dev/null
}
popd () {
    command popd "$@" > /dev/null
}

echo "* Configuring the build environment"
export VER="v1.2.0"
export ZIP="ptune-$VER.zip"
export SRCMOD="$PWD/module"

echo "* Packaging the module"
pushd "$SRCMOD" >&2
zip -r -0 -v "$ZIP" . > /dev/null
popd >&2
rm "$PWD/$ZIP" >/dev/null 2>&1
mv "$SRCMOD/$ZIP" "$PWD/$ZIP"

echo "* Done!"

if [ -d /sdcard ]; then
  rm "/sdcard/$ZIP" >/dev/null 2>&1
  mv "$ZIP" /sdcard/
  echo "-> /sdcard/$ZIP"
else
  echo "-> $ZIP"
fi
