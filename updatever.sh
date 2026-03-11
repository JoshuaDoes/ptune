#!/data/data/com.termux/files/usr/bin/bash

nano build.sh CHANGELOG.md module/module.prop module/patch.sh module/service.sh update.json
pushd ../powerpulse
nano main.go
./install.sh
popd
