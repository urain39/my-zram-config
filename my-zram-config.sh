#!/bin/sh

COMP_ALGO="lzo"
DEV_NUM="$(grep -c '^processor' /proc/cpuinfo)"
LOG_DIR="/var/log"
LOG_SIZE_KB="$((128*1024))"
LOG_COMP_ALGO="lz4"

_CFG_PATH="/etc/my-zram-config/config.conf"

if [ -e "$_CFG_PATH" ]; then
    . "$_CFG_PATH"
fi


start() {
    stop

    local mem_size_kb="$(awk '$1 == "MemTotal:" { print $2; exit 0 }' /proc/meminfo)"
    local per_size_kb="$(((mem_size_kb - LOG_SIZE_KB)  / DEV_NUM))"

    modprobe zram num_devices="$((DEV_NUM + 1))"

    for i in $(seq 0 $((DEV_NUM - 1))); do
        echo "$COMP_ALGO" > /sys/block/zram"$i"/comp_algorithm
        echo "$per_size_kb"KB > /sys/block/zram"$i"/disksize
        mkswap /dev/zram"$i"
        swapon /dev/zram"$i"
    done

    echo "$LOG_COMP_ALGO" > /sys/block/zram"$DEV_NUM"/comp_algorithm
    echo "$LOG_SIZE_KB"KB > /sys/block/zram"$DEV_NUM"/disksize
    mkfs.ext4 /dev/zram"$DEV_NUM"

    mkdir -p "$LOG_DIR".hdd
    mount --bind "$LOG_DIR" "$LOG_DIR".hdd
    mount /dev/zram"$DEV_NUM" "$LOG_DIR"

    rsync -ac "$LOG_DIR".hdd/ "$LOG_DIR"/
}

stop() {
    for i in $(seq 0 $((DEV_NUM - 1))); do
        if [ -b /dev/zram"$i" ]; then
            swapoff /dev/zram"$i"
        fi
    done

    awk -v LOG_DIR="$LOG_DIR" \
    'BEGIN {
        found=0
    }

    {
        if ($2 == LOG_DIR) {
            found=1
            exit 0
        }
    }

    END {
        if (found) {
            exit 0
        }

        exit 1
    }' /proc/mounts && {
        rsync -ac "$LOG_DIR"/ "$LOG_DIR".hdd/
        umount "$LOG_DIR".hdd
        umount "$LOG_DIR"
    }

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
