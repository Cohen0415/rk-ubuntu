#!/bin/bash -e

if [ -e /etc/Powermanager/triggerhappy.service ]; then
    cp /etc/Powermanager/triggerhappy.service /lib/systemd/system/triggerhappy.service
fi

if [ -e /etc/systemd/logind.conf ]; then
    sed -i "s/#HandlePowerKey=.*/HandlePowerKey=ignore/" /etc/systemd/logind.conf
fi

chmod 755 /etc /etc/gdm3 2>/dev/null || true
chmod 644 /etc/profile /etc/gdm3/custom.conf 2>/dev/null || true

user_name="${RK_UBUNTU_USER:-ubuntu}"

if [ -e /etc/gdm3/custom.conf ]; then
    sed -i "s/^AutomaticLogin[[:space:]]*=.*/AutomaticLogin = $user_name/" /etc/gdm3/custom.conf
fi

if id "$user_name" >/dev/null 2>&1; then
    chage -d 2020-01-01 "$user_name" || true
fi
