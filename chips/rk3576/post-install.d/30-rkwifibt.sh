#!/bin/bash -e

if [ -d /etc/wifi ]; then
    mkdir -p /vendor/etc
    if [ ! -e /vendor/etc/firmware ]; then
        ln -s /system/etc/firmware /vendor/etc/firmware
    fi
    [ -e /etc/wifi/rkwifibt.sh ] && mv /etc/wifi/rkwifibt.sh /etc/init.d/
    [ -e /etc/wifi/rk_wifi_init ] && mv /etc/wifi/rk_wifi_init /usr/bin/
    rm -rf /etc/wifi
fi

systemctl enable rkwifibt.service || true
