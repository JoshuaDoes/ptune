#!/data/data/com.termux/files/usr/bin/bash

chmod +x module/*.sh
chmod +x module/bin/*
sudo touch /data/adb/modules/ptune/wait
sudo ./module/service.sh
sudo rm /data/adb/modules/ptune/wait
