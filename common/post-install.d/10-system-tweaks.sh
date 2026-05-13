#!/bin/bash -e

if [ -e /etc/Powermanager/triggerhappy.service ]; then
    cp /etc/Powermanager/triggerhappy.service /lib/systemd/system/triggerhappy.service
fi

if [ -e /etc/systemd/logind.conf ]; then
    sed -i "s/#HandlePowerKey=.*/HandlePowerKey=ignore/" /etc/systemd/logind.conf
fi
