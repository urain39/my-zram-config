#!/bin/sh

install -m755 my-zram-config.sh /usr/local/bin/my-zram-config
install -Dm644 etc/my-zram-config/config.conf /etc/my-zram-config/config.conf
install -m755 openrc/my-zram-config.in /etc/init.d/my-zram-config

rc-update del my-zram-config boot 2> /dev/null
rc-update add my-zram-config default
