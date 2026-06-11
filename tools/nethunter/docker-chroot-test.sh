#!/usr/bin/env bash
set -u

SCRIPT_NAME="${0##*/}"
DOCKER_DATA_ROOT="${DOCKER_DATA_ROOT:-/var/lib/docker}"
DOCKER_LOG="${DOCKER_LOG:-/tmp/nethunter-dockerd.log}"
DOCKER_PIDFILE="${DOCKER_PIDFILE:-/tmp/nethunter-dockerd.pid}"
DOCKER_STORAGE_DRIVER="${DOCKER_STORAGE_DRIVER:-auto}"
TEST_NETWORK="${TEST_NETWORK:-nhtest}"
TEST_TIMEOUT="${TEST_TIMEOUT:-60}"

log() {
    printf '[%s] %s\n' "$SCRIPT_NAME" "$*"
}

die() {
    printf '[%s] ERROR: %s\n' "$SCRIPT_NAME" "$*" >&2
    exit 1
}

run() {
    log "+ $*"
    "$@" || die "command failed: $*"
}

require_root() {
    [ "$(id -u)" = "0" ] || die "run this inside the Kali chroot as root"
}

usage() {
    cat <<EOF
Usage: $SCRIPT_NAME <command>

Commands:
  setup       Install packages, select iptables-legacy, mount cgroups.
  start       Start dockerd in the background.
  test        Run Docker smoke tests.
  stop        Stop dockerd started by this script.
  cleanup     Remove the test network and stop dockerd.
  purge       cleanup, then delete Docker data root: $DOCKER_DATA_ROOT.
  all         setup, start, test, cleanup.
  status      Show Docker/cgroup/kernel status.

Environment:
  DOCKER_DATA_ROOT       Default: /var/lib/docker
  DOCKER_STORAGE_DRIVER  auto, overlay2, fuse-overlayfs, or vfs. Default: auto
  DOCKER_LOG             Default: /tmp/nethunter-dockerd.log
  TEST_TIMEOUT           Default: 60

Run inside the Kali NetHunter chroot, not Android adb shell.
EOF
}

is_mounted() {
    grep -qs " $1 " /proc/mounts
}

ensure_basic_mounts() {
    mkdir -p /proc /sys /dev /run /var/run
    is_mounted /proc || mount -t proc proc /proc 2>/dev/null || true
    is_mounted /sys || mount -t sysfs sysfs /sys 2>/dev/null || true
    mkdir -p /sys/fs/cgroup
}

select_iptables_legacy() {
    if command -v update-alternatives >/dev/null 2>&1; then
        update-alternatives --set iptables /usr/sbin/iptables-legacy 2>/dev/null || true
        update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy 2>/dev/null || true
    fi

    if command -v iptables >/dev/null 2>&1; then
        iptables --version || true
    fi
}

install_packages() {
    command -v apt-get >/dev/null 2>&1 || {
        log "apt-get not found; skipping package install"
        return 0
    }

    export DEBIAN_FRONTEND=noninteractive
    run apt-get update
    run apt-get install -y \
        docker.io \
        iptables \
        iproute2 \
        ca-certificates \
        curl \
        uidmap \
        fuse-overlayfs
}

mount_cgroup2() {
    mkdir -p /sys/fs/cgroup

    if [ -f /sys/fs/cgroup/cgroup.controllers ]; then
        log "cgroup v2 is already mounted"
    elif ! is_mounted /sys/fs/cgroup; then
        mount -t cgroup2 none /sys/fs/cgroup 2>/dev/null || return 1
        log "mounted cgroup v2"
    else
        return 1
    fi

    if [ -f /sys/fs/cgroup/cgroup.controllers ]; then
        log "available cgroup v2 controllers: $(cat /sys/fs/cgroup/cgroup.controllers)"
        for c in $(cat /sys/fs/cgroup/cgroup.controllers); do
            echo "+$c" > /sys/fs/cgroup/cgroup.subtree_control 2>/dev/null || true
        done
        return 0
    fi

    return 1
}

mount_cgroup1_controller() {
    local name="$1"
    local opts="$2"
    local path="/sys/fs/cgroup/$name"

    mkdir -p "$path"
    is_mounted "$path" || mount -t cgroup -o "$opts" none "$path" 2>/dev/null || true
}

mount_cgroup1() {
    mount_cgroup1_controller "cpu,cpuacct" "cpu,cpuacct"
    mount_cgroup1_controller "cpuset" "cpuset"
    mount_cgroup1_controller "devices" "devices"
    mount_cgroup1_controller "freezer" "freezer"
    mount_cgroup1_controller "memory" "memory"
    mount_cgroup1_controller "pids" "pids"
    mount_cgroup1_controller "blkio" "blkio"
    mount_cgroup1_controller "net_cls,net_prio" "net_cls,net_prio"
}

mount_cgroups() {
    ensure_basic_mounts
    mount_cgroup2 || {
        log "cgroup v2 unavailable here; trying cgroup v1 mounts"
        mount_cgroup1
    }
    mount | grep cgroup || true
}

check_kernel_config() {
    local missing=0
    local cfg="/tmp/nethunter-kernel-config.$$"

    if [ ! -r /proc/config.gz ]; then
        log "/proc/config.gz is not readable; skipping kernel config check"
        return 0
    fi

    zcat /proc/config.gz > "$cfg" 2>/dev/null || {
        rm -f "$cfg"
        log "could not decompress /proc/config.gz; skipping kernel config check"
        return 0
    }

    for opt in \
        CONFIG_NAMESPACES \
        CONFIG_NET_NS \
        CONFIG_PID_NS \
        CONFIG_IPC_NS \
        CONFIG_UTS_NS \
        CONFIG_USER_NS \
        CONFIG_CGROUPS \
        CONFIG_CGROUP_DEVICE \
        CONFIG_CGROUP_PIDS \
        CONFIG_MEMCG \
        CONFIG_VETH \
        CONFIG_BRIDGE \
        CONFIG_BRIDGE_NETFILTER \
        CONFIG_IP_NF_TARGET_MASQUERADE \
        CONFIG_NETFILTER_XT_MATCH_ADDRTYPE \
        CONFIG_NETFILTER_XT_MATCH_CONNTRACK \
        CONFIG_OVERLAY_FS \
        CONFIG_SECCOMP \
        CONFIG_SECCOMP_FILTER
    do
        if ! grep -q "^$opt=y" "$cfg"; then
            log "missing or disabled: $opt"
            missing=1
        fi
    done

    rm -f "$cfg"

    if [ "$missing" -ne 0 ]; then
        log "kernel config has missing Docker basics; tests may fail"
    else
        log "kernel config has Docker basics"
    fi
}

setup() {
    require_root
    unset LD_PRELOAD
    install_packages
    select_iptables_legacy
    mount_cgroups
    check_kernel_config
}

dockerd_running() {
    if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

storage_driver_args() {
    case "$DOCKER_STORAGE_DRIVER" in
        auto|overlay2)
            printf '%s\n' "--storage-driver=overlay2"
            ;;
        fuse-overlayfs)
            printf '%s\n' "--storage-driver=fuse-overlayfs"
            ;;
        vfs)
            printf '%s\n' "--storage-driver=vfs"
            ;;
        *)
            die "unknown DOCKER_STORAGE_DRIVER=$DOCKER_STORAGE_DRIVER"
            ;;
    esac
}

start_dockerd_once() {
    local driver="$1"

    : > "$DOCKER_LOG"
    log "starting dockerd with storage driver: $driver"

    dockerd \
        --host=unix:///var/run/docker.sock \
        --data-root="$DOCKER_DATA_ROOT" \
        --exec-opt native.cgroupdriver=cgroupfs \
        "--storage-driver=$driver" \
        --iptables=true \
        --ip-forward=true \
        --debug >> "$DOCKER_LOG" 2>&1 &

    echo "$!" > "$DOCKER_PIDFILE"

    local i=0
    while [ "$i" -lt "$TEST_TIMEOUT" ]; do
        if dockerd_running; then
            log "dockerd is ready"
            return 0
        fi
        if ! kill -0 "$(cat "$DOCKER_PIDFILE")" 2>/dev/null; then
            log "dockerd exited early with $driver"
            tail -80 "$DOCKER_LOG" || true
            rm -f "$DOCKER_PIDFILE"
            return 1
        fi
        i=$((i + 1))
        sleep 1
    done

    log "dockerd did not become ready with $driver"
    tail -80 "$DOCKER_LOG" || true
    stop_dockerd
    return 1
}

start_dockerd() {
    require_root
    unset LD_PRELOAD
    ensure_basic_mounts
    mount_cgroups
    mkdir -p "$DOCKER_DATA_ROOT" /var/run /run

    if dockerd_running; then
        log "dockerd is already running"
        return 0
    fi

    command -v dockerd >/dev/null 2>&1 || die "dockerd not found; run '$SCRIPT_NAME setup' first"

    if [ "$DOCKER_STORAGE_DRIVER" = "auto" ]; then
        start_dockerd_once overlay2 && return 0
        command -v fuse-overlayfs >/dev/null 2>&1 && start_dockerd_once fuse-overlayfs && return 0
        start_dockerd_once vfs && return 0
        die "failed to start dockerd with overlay2, fuse-overlayfs, and vfs"
    fi

    start_dockerd_once "$DOCKER_STORAGE_DRIVER"
}

stop_dockerd() {
    if [ -f "$DOCKER_PIDFILE" ]; then
        local pid
        pid="$(cat "$DOCKER_PIDFILE" 2>/dev/null || true)"
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            log "stopping dockerd pid $pid"
            kill "$pid" 2>/dev/null || true
            sleep 2
            kill -9 "$pid" 2>/dev/null || true
        fi
        rm -f "$DOCKER_PIDFILE"
    else
        log "no $DOCKER_PIDFILE; leaving any system dockerd alone"
    fi
}

docker_test() {
    require_root
    unset LD_PRELOAD
    dockerd_running || die "dockerd is not running; run '$SCRIPT_NAME start' first"

    run docker version
    run docker info
    run docker run --rm hello-world
    run docker run --rm alpine uname -a
    run docker run --rm alpine sh -c 'ip addr; ip route'

    docker network rm "$TEST_NETWORK" >/dev/null 2>&1 || true
    run docker network create "$TEST_NETWORK"
    run docker run --rm --network "$TEST_NETWORK" alpine ip addr
    docker network rm "$TEST_NETWORK" >/dev/null 2>&1 || true

    log "Docker smoke tests passed"
}

cleanup() {
    require_root
    unset LD_PRELOAD
    if dockerd_running; then
        docker network rm "$TEST_NETWORK" >/dev/null 2>&1 || true
    fi
    stop_dockerd
    log "cleanup done"
}

purge() {
    cleanup
    log "deleting Docker data root: $DOCKER_DATA_ROOT"
    rm -rf "$DOCKER_DATA_ROOT"
}

status() {
    require_root
    unset LD_PRELOAD
    uname -a || true
    if [ -r /proc/config.gz ]; then
        zcat /proc/config.gz | grep -E 'CONFIG_(NAMESPACES|USER_NS|PID_NS|NET_NS|CGROUP_DEVICE|CGROUP_PIDS|BLK_CGROUP|VETH|BRIDGE|BRIDGE_NETFILTER|IP_VS|NETFILTER_XT_MATCH_IPVS|IPVLAN|VXLAN|NET_CLS_CGROUP|CGROUP_NET_PRIO|CGROUP_NET_CLASSID|OVERLAY_FS)=' || true
    fi
    mount | grep cgroup || true
    command -v iptables >/dev/null 2>&1 && iptables --version || true
    command -v docker >/dev/null 2>&1 && docker info || true
}

all() {
    trap cleanup EXIT
    setup
    start_dockerd
    docker_test
    trap - EXIT
    cleanup
}

cmd="${1:-}"
case "$cmd" in
    setup) setup ;;
    start) start_dockerd ;;
    test) docker_test ;;
    stop) stop_dockerd ;;
    cleanup) cleanup ;;
    purge) purge ;;
    all) all ;;
    status) status ;;
    -h|--help|help|"") usage ;;
    *) usage; die "unknown command: $cmd" ;;
esac
