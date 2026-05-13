#!/bin/bash -e

if [ -d /etc/3A ]; then
    mkdir -p /etc/iqfiles
    [ -d /etc/3A/bin ] && mv /etc/3A/bin/* /usr/bin/ 2>/dev/null || true
    [ -d /etc/3A/iqfiles ] && mv /etc/3A/iqfiles/* /etc/iqfiles/ 2>/dev/null || true
    rm -rf /etc/3A
fi
