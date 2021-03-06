#!/bin/sh

COMP_ALGO="lzo"
DEV_NUM="$(grep -c '^processor' /proc/cpuinfo)"
LOG_DIR="/var/log"
LOG_SIZE_KB="$((128*1024))"
LOG_COMP_ALGO="lz4"
RAM_HOME="off"
HOME_DIR="/home"
STATIC_DIR="/static"
RSYNC_ARGS="-auy --inplace --no-whole-file --delete-after"

_NAME=my-zram-config
_CFG_PATH=/etc/"$_NAME"/config.conf
_RUN_CFG_PATH=/run/"$_NAME".conf
_LOG_PATH="$LOG_DIR".hdd/"$_NAME".log


if [ -f "$_RUN_CFG_PATH" ]; then
    # shellcheck disable=1090
    . "$_RUN_CFG_PATH"
else
    if [ -f "$_CFG_PATH" ]; then
        cat "$_CFG_PATH" > "$_RUN_CFG_PATH"
        # shellcheck disable=1090
        . "$_CFG_PATH"
    fi
fi


_is_mounted() {
    awk -v mnt_pnt="$1" \
    'BEGIN {
        found=0
    }

    {
        if ($2 == mnt_pnt) {
            found=1
            exit 0
        }
    }

    END {
        exit !found
    }' /proc/mounts
}


correct() {
    if [ "$RAM_HOME" = "on" ]; then
        mkdir -p "$STATIC_DIR"

        if [ "$(stat -c "%u%g%a" "$STATIC_DIR")" != "001777" ]; then
            chown root:root "$STATIC_DIR"
            chmod 1777 "$STATIC_DIR"
        fi
    fi
}

start() {
    stop

    local mem_size_kb="" avg_size_kb=""

    mem_size_kb="$(awk '$1 == "MemTotal:" { print $2; exit 0 }' /proc/meminfo)"
    avg_size_kb="$(((mem_size_kb - LOG_SIZE_KB)  / DEV_NUM))"

    modprobe zram num_devices="$((DEV_NUM + 1))"

    local i=
    for i in $(seq 0 $((DEV_NUM - 1))); do
        echo "$COMP_ALGO" > /sys/block/zram"$i"/comp_algorithm
        echo "$avg_size_kb"KB > /sys/block/zram"$i"/disksize
        mkswap /dev/zram"$i"
        swapon /dev/zram"$i"
    done

    echo "$LOG_COMP_ALGO" > /sys/block/zram"$DEV_NUM"/comp_algorithm
    echo "$LOG_SIZE_KB"KB > /sys/block/zram"$DEV_NUM"/disksize
    mkfs.ext4 /dev/zram"$DEV_NUM"

    mkdir -p "$LOG_DIR".hdd
    mount --bind "$LOG_DIR" "$LOG_DIR".hdd
    mount /dev/zram"$DEV_NUM" "$LOG_DIR"

    # shellcheck disable=SC2086
    rsync $RSYNC_ARGS "$LOG_DIR".hdd/ "$LOG_DIR"/

    if [ "$RAM_HOME" = "on" ]; then
        mkdir -p "$HOME_DIR".hdd
        mount --bind "$HOME_DIR" "$HOME_DIR".hdd
        mount tmpfs -t tmpfs "$HOME_DIR"

        # shellcheck disable=SC2086
        rsync $RSYNC_ARGS "$HOME_DIR".hdd/ "$HOME_DIR"/
    fi
}

stop() {
    _is_mounted "$HOME_DIR" && {
        # shellcheck disable=SC2086
        rsync $RSYNC_ARGS "$HOME_DIR"/ "$HOME_DIR".hdd/
        sync

        umount -l "$HOME_DIR"
        umount -l "$HOME_DIR".hdd
    }

    _is_mounted "$LOG_DIR" && {
        # shellcheck disable=SC2086
        rsync $RSYNC_ARGS "$LOG_DIR"/ "$LOG_DIR".hdd/
        sync && iostat -m > "$_LOG_PATH"

        umount -l "$LOG_DIR"
        umount -l "$LOG_DIR".hdd
    }

    local i=
    for i in $(seq 0 $((DEV_NUM - 1))); do
        if [ -b /dev/zram"$i" ]; then
            swapoff /dev/zram"$i"
        fi
    done

    #modprobe -r zram
}


case "$1" in
"correct")
    correct
    ;;
"start")
    start
    ;;
"stop")
    stop
    ;;
"status")
    _is_mounted "$LOG_DIR" #|| _is_mounted "$HOME_DIR"
    exit "$?"
    ;;
esac
