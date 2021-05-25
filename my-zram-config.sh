#!/bin/sh

COMP_ALGO="lzo"
DEV_NUM="$(grep -c '^processor' /proc/cpuinfo)"

if [ -e /etc/my-zram-config/config.conf ]; then
    . /etc/my-zram-config/config.conf
fi


start() {
    stop

    local mem_size_kb="$(awk '$1 == "MemTotal:" { print $2; exit 0 }' /proc/meminfo)"
    local per_size_kb="$((mem_size_kb / DEV_NUM))"

    modprobe zram num_devices="$DEV_NUM"

    for i in $(seq 0 $((DEV_NUM - 1))); do
        echo "$COMP_ALGO" > /sys/block/zram"$i"/comp_algorithm
        echo "$per_size_kb"KB > /sys/block/zram"$i"/disksize
        mkswap /dev/zram"$i"
        swapon /dev/zram"$i"
    done
}

stop() {
    for i in $(seq 0 $((DEV_NUM - 1))); do
        if [ -e /dev/zram"$i" ]; then
            swapoff /dev/zram"$i"
        fi
    done

    modprobe -r zram
}


case "$1" in
"start")
    start
    ;;
"stop")
    stop
    ;;
esac
