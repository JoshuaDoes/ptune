#!/bin/bash

export VER="v2.0.0-alpha12"
export TAG="ptune-$VER"
export ZIP="$TAG.zip"
export DIF="$TAG.diff"
export SRCMOD="$PWD/module"

# Hide output from pushd/popd
pushd () {
    command pushd "$@" > /dev/null
}
popd () {
    command popd "$@" > /dev/null
}

echo "* Packaging the module"
pushd "$SRCMOD" >&2
zip -r -0 -v "$ZIP" . > /dev/null
popd >&2
rm "$ZIP" >/dev/null 2>&1
mv "$SRCMOD/$ZIP" "$ZIP"

if [ -d .git ]; then
  git diff HEAD > "$DIF"
fi

echo "* Done!"

if [ -d /sdcard ]; then
  rm "/sdcard/$ZIP" >/dev/null 2>&1
  if [ -f "$DIF" ]; then
    cat "$DIF"
    mv "$DIF" /sdcard/
    echo "-> /sdcard/$DIF"
  fi
  mv "$ZIP" /sdcard/
  echo "-> /sdcard/$ZIP"
else
  if [ -f "$DIF" ]; then echo "-> $DIF"; fi
  echo "-> $ZIP"
fi
