#!/bin/bash

# Stop the Xray service
sudo systemctl stop xray
sudo rm /usr/local/bin/xray
sudo rm /etc/systemd/system/xray.service
sudo rm /usr/local/etc/xray/config.json
sudo rm /usr/local/share/xray/geoip.dat
sudo rm /usr/local/share/xray/geosite.dat
sudo rm /etc/systemd/system/xray@.service

# Reload the systemd daemon
sudo systemctl daemon-reload

# Remove any leftover Xray files or directories
sudo rm -rf /var/log/xray /var/lib/xray

clear
echo -e "\e[1;32mReality已卸载\033[0m"
