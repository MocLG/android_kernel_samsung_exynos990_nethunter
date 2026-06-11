#!/usr/bin/env bash
set -u
exec 2>&1

SCRIPT_NAME="${0##*/}"
DOCKER_DATA_ROOT="${DOCKER_DATA_ROOT:-/var/lib/docker}"
DOCKER_LOG="${DOCKER_LOG:-/tmp/nethunter-dockerd.log}"
DOCKER_PIDFILE="${DOCKER_PIDFILE:-/tmp/nethunter-dockerd.pid}"
DOCKER_STORAGE_DRIVER="${DOCKER_STORAGE_DRIVER:-auto}"
DOCKER_BRIDGE_CIDR="${DOCKER_BRIDGE_CIDR:-172.17.0.1/16}"
DOCKER_NAT_CIDR="${DOCKER_NAT_CIDR:-172.16.0.0/12}"
DOCKER_DNS="${DOCKER_DNS:-1.1.1.1 8.8.8.8}"
DOCKER_KILL_EXISTING="${DOCKER_KILL_EXISTING:-1}"
DOCKER_EXTERNAL_CONTAINERD="${DOCKER_EXTERNAL_CONTAINERD:-1}"
DOCKER_CONTAINERD_SNAPSHOTTER="${DOCKER_CONTAINERD_SNAPSHOTTER:-auto}"
DOCKER_UNSHARE_MOUNT_NS="${DOCKER_UNSHARE_MOUNT_NS:-1}"
DOCKER_FIX_MOUNT_PROPAGATION="${DOCKER_FIX_MOUNT_PROPAGATION:-1}"
DOCKER_RUNC_WRAPPER="${DOCKER_RUNC_WRAPPER:-1}"
RUNC_WRAPPER_PATH="${RUNC_WRAPPER_PATH:-/tmp/nethunter-runc-wrapper}"
RUNC_WRAPPER_LOG="${RUNC_WRAPPER_LOG:-/tmp/nethunter-runc-wrapper.log}"
CONTAINERD_ROOT="${CONTAINERD_ROOT:-/var/lib/nethunter-containerd}"
CONTAINERD_STATE="${CONTAINERD_STATE:-/run/nethunter-containerd}"
CONTAINERD_CONFIG="${CONTAINERD_CONFIG:-/tmp/nethunter-containerd.toml}"
CONTAINERD_LOG="${CONTAINERD_LOG:-/tmp/nethunter-containerd.log}"
CONTAINERD_PIDFILE="${CONTAINERD_PIDFILE:-/tmp/nethunter-containerd.pid}"
CONTAINERD_SOCK="${CONTAINERD_SOCK:-/run/nethunter-containerd/containerd.sock}"
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
  DOCKER_STORAGE_DRIVER  auto, overlayfs, native, overlay2, fuse-overlayfs, or vfs. Default: auto
  DOCKER_BRIDGE_CIDR     Docker bridge address. Default: 172.17.0.1/16
  DOCKER_NAT_CIDR        CIDR to masquerade manually. Default: 172.16.0.0/12
  DOCKER_DNS             Space-separated DNS servers. Default: 1.1.1.1 8.8.8.8
  DOCKER_KILL_EXISTING   Kill stale dockerd/containerd before start. Default: 1
  DOCKER_EXTERNAL_CONTAINERD
                         Start a separate containerd with bad snapshotters disabled. Default: 1
  DOCKER_CONTAINERD_SNAPSHOTTER
                         auto, 1, or 0. Default: auto, enabled with external containerd.
  DOCKER_UNSHARE_MOUNT_NS
                         Re-exec inside a private mount namespace. Default: 1
  DOCKER_FIX_MOUNT_PROPAGATION
                         Make / and Docker data root rslave before dockerd. Default: 1
  DOCKER_RUNC_WRAPPER    Patch OCI rootfsPropagation before runc create. Default: 1
  RUNC_WRAPPER_LOG       Default: /tmp/nethunter-runc-wrapper.log
  CONTAINERD_ROOT        Default: /var/lib/nethunter-containerd
  CONTAINERD_STATE       Default: /run/nethunter-containerd
  CONTAINERD_LOG         Default: /tmp/nethunter-containerd.log
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

maybe_reexec_mount_namespace() {
    local cmd="${1:-}"

    [ "$DOCKER_UNSHARE_MOUNT_NS" = "1" ] || return 0
    [ "${NH_DOCKER_MOUNT_NS:-0}" = "1" ] && return 0

    case "$cmd" in
        start|test|cleanup|purge|all|status)
            ;;
        *)
            return 0
            ;;
    esac

    command -v unshare >/dev/null 2>&1 || {
        log "unshare not found; continuing in current mount namespace"
        return 0
    }

    if unshare -m true 2>/dev/null; then
        log "re-execing inside a private mount namespace"
        NH_DOCKER_MOUNT_NS=1 exec unshare -m -- "$0" "$@"
    fi

    log "mount namespace unshare failed; continuing in current mount namespace"
}

prepare_mount_propagation() {
    [ "$DOCKER_FIX_MOUNT_PROPAGATION" = "1" ] || return 0

    log "preparing Docker mount propagation"

    if ! mount --make-rslave / 2>/dev/null; then
        log "making chroot root a bind mount for propagation setup"
        mount --bind / / 2>/dev/null || {
            log "failed to bind-mount /; Docker layer unpack may fail"
            return 0
        }
        mount --make-rslave / 2>/dev/null || {
            log "failed to make / rslave; Docker layer unpack may fail"
            return 0
        }
    fi

    mkdir -p "$DOCKER_DATA_ROOT"
    mount --bind "$DOCKER_DATA_ROOT" "$DOCKER_DATA_ROOT" 2>/dev/null || true
    mount --make-rslave "$DOCKER_DATA_ROOT" 2>/dev/null || true
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

iptables_filter_works() {
    local chain="NHTEST_$$_FILTER"

    command -v iptables >/dev/null 2>&1 || return 1
    iptables -t filter -N "$chain" 2>/dev/null || return 1
    iptables -t filter -X "$chain" 2>/dev/null || true
    return 0
}

default_route_iface() {
    ip route get 1.1.1.1 2>/dev/null | awk '
        {
            for (i = 1; i <= NF; i++) {
                if ($i == "dev") {
                    print $(i + 1)
                    exit
                }
            }
        }
    '
}

enable_ip_forwarding() {
    [ -w /proc/sys/net/ipv4/ip_forward ] && echo 1 > /proc/sys/net/ipv4/ip_forward || true
    [ -w /proc/sys/net/ipv6/conf/all/forwarding ] && echo 1 > /proc/sys/net/ipv6/conf/all/forwarding || true
}

iptables_add_once() {
    local table="$1"
    local chain="$2"
    shift 2

    iptables -t "$table" -C "$chain" "$@" 2>/dev/null && return 0
    iptables -t "$table" -A "$chain" "$@" 2>/dev/null || return 1
}

iptables_delete_all() {
    local table="$1"
    local chain="$2"
    shift 2

    while iptables -t "$table" -D "$chain" "$@" 2>/dev/null; do
        :
    done
}

setup_manual_nat() {
    local iface

    command -v iptables >/dev/null 2>&1 || {
        log "iptables not found; container internet through NAT cannot be configured"
        return 1
    }

    enable_ip_forwarding
    iface="$(default_route_iface)"

    if [ -n "$iface" ]; then
        log "adding manual Docker NAT for $DOCKER_NAT_CIDR via $iface"
        iptables_add_once nat POSTROUTING -s "$DOCKER_NAT_CIDR" -o "$iface" -j MASQUERADE || {
            log "failed to add interface-specific NAT rule; trying generic NAT"
            iptables_add_once nat POSTROUTING -s "$DOCKER_NAT_CIDR" -j MASQUERADE || return 1
        }
    else
        log "default route interface not found; adding generic Docker NAT for $DOCKER_NAT_CIDR"
        iptables_add_once nat POSTROUTING -s "$DOCKER_NAT_CIDR" -j MASQUERADE || return 1
    fi

    if iptables_filter_works; then
        iptables_add_once filter FORWARD -s "$DOCKER_NAT_CIDR" -j ACCEPT || true
        iptables_add_once filter FORWARD -d "$DOCKER_NAT_CIDR" -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT || true
    else
        log "iptables filter table cannot create chains; relying on existing FORWARD policy"
    fi
}

cleanup_manual_nat() {
    local iface

    command -v iptables >/dev/null 2>&1 || return 0
    iface="$(default_route_iface)"

    if [ -n "$iface" ]; then
        iptables_delete_all nat POSTROUTING -s "$DOCKER_NAT_CIDR" -o "$iface" -j MASQUERADE
    fi
    iptables_delete_all nat POSTROUTING -s "$DOCKER_NAT_CIDR" -j MASQUERADE

    if iptables_filter_works; then
        iptables_delete_all filter FORWARD -s "$DOCKER_NAT_CIDR" -j ACCEPT
        iptables_delete_all filter FORWARD -d "$DOCKER_NAT_CIDR" -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
    fi
}

kill_matching_processes() {
    local pattern="$1"
    local signal="${2:-TERM}"
    local pid

    command -v ps >/dev/null 2>&1 || return 0

    ps -eo pid=,args= 2>/dev/null | awk -v pat="$pattern" -v self="$$" '
        index($0, pat) && $1 != self && $0 !~ /awk -v pat=/ {
            print $1
        }
    ' | while read -r pid; do
        [ -n "$pid" ] || continue
        log "stopping stale process matching '$pattern': pid $pid (SIG$signal)"
        kill "-$signal" "$pid" 2>/dev/null || true
    done
}

clear_stale_runtime() {
    [ "$DOCKER_KILL_EXISTING" = "1" ] || return 0

    kill_matching_processes "dockerd" TERM
    kill_matching_processes "/var/run/docker/containerd" TERM
    kill_matching_processes "/run/docker/containerd" TERM
    kill_matching_processes "$CONTAINERD_CONFIG" TERM
    kill_matching_processes "$CONTAINERD_STATE" TERM
    kill_matching_processes "containerd-shim" TERM
    sleep 1
    kill_matching_processes "dockerd" KILL
    kill_matching_processes "/var/run/docker/containerd" KILL
    kill_matching_processes "/run/docker/containerd" KILL
    kill_matching_processes "$CONTAINERD_CONFIG" KILL
    kill_matching_processes "$CONTAINERD_STATE" KILL
    kill_matching_processes "containerd-shim" KILL

    rm -f /var/run/docker.sock /run/docker.sock
    rm -rf /var/run/docker /run/docker
    rm -f "$CONTAINERD_SOCK" "$CONTAINERD_SOCK.ttrpc"
    rm -f "$RUNC_WRAPPER_PATH" "$RUNC_WRAPPER_LOG" "$(dirname "$RUNC_WRAPPER_PATH")/nethunter-runc-preload.so"
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
        crun \
        iptables \
        iproute2 \
        util-linux \
        python3-minimal \
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
    if iptables_filter_works; then
        log "iptables filter table can create chains"
    else
        log "iptables filter table cannot create chains; dockerd will use manual NAT fallback"
    fi
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
        auto)
            return 0
            ;;
        overlayfs|native|overlay2)
            printf '%s\n' "--storage-driver=$DOCKER_STORAGE_DRIVER"
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

dockerd_supports_feature_flag() {
    dockerd --help 2>/dev/null | grep -q -- '--feature'
}

dockerd_containerd_snapshotter_enabled() {
    [ "$(dockerd_containerd_snapshotter_value)" = "true" ]
}

dockerd_containerd_snapshotter_value() {
    case "$DOCKER_CONTAINERD_SNAPSHOTTER" in
        auto)
            if [ "$DOCKER_EXTERNAL_CONTAINERD" = "1" ] && [ -S "$CONTAINERD_SOCK" ]; then
                printf 'true\n'
            else
                printf 'false\n'
            fi
            ;;
        1|true|yes|on)
            printf 'true\n'
            ;;
        0|false|no|off)
            printf 'false\n'
            ;;
        *)
            die "unknown DOCKER_CONTAINERD_SNAPSHOTTER=$DOCKER_CONTAINERD_SNAPSHOTTER"
            ;;
    esac
}

write_runc_wrapper() {
    [ "$DOCKER_RUNC_WRAPPER" = "1" ] || return 0
    command -v crun >/dev/null 2>&1 || command -v runc >/dev/null 2>&1 || {
        log "neither crun nor runc found; cannot install runc wrapper"
        return 1
    }
    command -v python3 >/dev/null 2>&1 || {
        log "python3 not found; cannot patch OCI runtime spec safely"
        return 1
    }

    if command -v crun >/dev/null 2>&1; then
        log "using crun as OCI runtime"
    else
        log "using runc as OCI runtime"
    fi

    cat > "$RUNC_WRAPPER_PATH" <<'EOF'
#!/usr/bin/env sh
set -eu

USING_CRUN=0
if command -v crun >/dev/null 2>&1; then
    REAL_RUNC="${NETHUNTER_REAL_RUNC:-$(command -v crun)}"
    USING_CRUN=1
elif command -v runc >/dev/null 2>&1; then
    REAL_RUNC="${NETHUNTER_REAL_RUNC:-$(command -v runc)}"
else
    echo "neither crun nor runc found" >&2
    exit 1
fi
LOG="${NETHUNTER_RUNC_LOG:-/tmp/nethunter-runc-wrapper.log}"
bundle=""
prev=""

for arg in "$@"; do
    if [ "$prev" = "--bundle" ] || [ "$prev" = "-b" ]; then
        bundle="$arg"
        break
    fi
    case "$arg" in
        --bundle=*)
            bundle="${arg#--bundle=}"
            break
            ;;
        -b=*)
            bundle="${arg#-b=}"
            break
            ;;
    esac
    prev="$arg"
done

if [ -n "$bundle" ] && [ -f "$bundle/config.json" ] && command -v python3 >/dev/null 2>&1; then
    python3 - "$bundle/config.json" "$LOG" <<'PY'
import json
import os
import sys

path = sys.argv[1]
log_path = sys.argv[2]

try:
    with open(path, "r", encoding="utf-8") as f:
        spec = json.load(f)
except Exception as exc:
    with open(log_path, "a", encoding="utf-8") as log:
        log.write(f"failed to read {path}: {exc}\n")
    sys.exit(0)

linux = spec.get("linux")
changed = False
old = None
rootfs_path = None

root = spec.get("root")
if isinstance(root, dict):
    rp = root.get("path", "")
    if rp:
        if not os.path.isabs(rp):
            rp = os.path.join(os.path.dirname(path), rp)
        rootfs_path = rp

ns_removed = False
if isinstance(linux, dict):
    old = linux.pop("rootfsPropagation", None) if "rootfsPropagation" in linux else None
    linux["rootfsPropagation"] = ""
    ns_list = linux.get("namespaces")
    if isinstance(ns_list, list):
        before = len(ns_list)
        linux["namespaces"] = [ns for ns in ns_list if not (isinstance(ns, dict) and ns.get("type") == "mount")]
        ns_removed = len(linux["namespaces"]) < before
        if ns_removed:
            changed = True

if old is None or old != "":
    changed = True

if changed:
    tmp = path + ".nethunter.tmp"
    try:
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(spec, f, separators=(",", ":"))
        os.replace(tmp, path)
        with open(log_path, "a", encoding="utf-8") as log:
            log.write(f"set linux.rootfsPropagation=\"\" (was {old!r}) in {path}\n")
            if ns_removed:
                log.write(f"removed mount namespace from config.json\n")
    except Exception as exc:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        with open(log_path, "a", encoding="utf-8") as log:
            log.write(f"failed to patch {path}: {exc}\n")

if rootfs_path and os.path.isdir(rootfs_path):
    with open(log_path, "a", encoding="utf-8") as log:
        log.write(f"rootfs_host_path={rootfs_path}\n")
PY

fi

# Rebuild args string, filtering out --cgroup-manager
new_args=""
skip_next=0
cmd=""
for arg in "$@"; do
    if [ "$skip_next" = "1" ]; then
        skip_next=0
        continue
    fi
    case "$arg" in
        --cgroup-manager=*) continue ;;
        --cgroup-manager) skip_next=1; continue ;;
    esac
    case "$arg" in
        create|run|exec)
            cmd="$arg"
            if [ "$USING_CRUN" = "1" ]; then
                new_args="$new_args --cgroup-manager=disabled"
            fi
            ;;
    esac
    new_args="$new_args${new_args:+ }$arg"
done

exec "$REAL_RUNC" $new_args
EOF

    chmod 0755 "$RUNC_WRAPPER_PATH" || return 1
    : > "$RUNC_WRAPPER_LOG"
    log "installed runc wrapper at $RUNC_WRAPPER_PATH"
}

write_containerd_config() {
    local cfg_err="$CONTAINERD_LOG.config"

    command -v containerd >/dev/null 2>&1 || return 1

    mkdir -p "$(dirname "$CONTAINERD_CONFIG")" "$(dirname "$CONTAINERD_LOG")"
    log "using $(containerd --version 2>/dev/null || printf 'containerd')"
    containerd config default > "$CONTAINERD_CONFIG" 2>"$cfg_err" || {
        log "containerd config default failed"
        tail -40 "$cfg_err" 2>/dev/null || true
        return 1
    }

    sed -i \
        -e "s|^root = .*|root = '$CONTAINERD_ROOT'|" \
        -e "s|^state = .*|state = '$CONTAINERD_STATE'|" \
        -e "s|/run/containerd/containerd.sock.ttrpc|$CONTAINERD_SOCK.ttrpc|g" \
        -e "s|/run/containerd/containerd.sock|$CONTAINERD_SOCK|g" \
        -e "s|^disabled_plugins = .*|disabled_plugins = ['io.containerd.snapshotter.v1.blockfile', 'io.containerd.snapshotter.v1.btrfs', 'io.containerd.snapshotter.v1.devmapper', 'io.containerd.snapshotter.v1.erofs', 'io.containerd.snapshotter.v1.zfs', 'io.containerd.grpc.v1.cri', 'io.containerd.cri.v1.images', 'io.containerd.cri.v1.runtime']|" \
        "$CONTAINERD_CONFIG" || {
        log "failed to edit generated containerd config"
        return 1
    }

    if ! grep -q "io.containerd.snapshotter.v1.btrfs" "$CONTAINERD_CONFIG"; then
        log "generated containerd config is missing disabled snapshotters"
        return 1
    fi

    if grep -q "/run/containerd/containerd.sock" "$CONTAINERD_CONFIG"; then
        log "generated containerd config still references /run/containerd"
        grep -n "/run/containerd/containerd.sock" "$CONTAINERD_CONFIG" || true
        return 1
    fi

    return 0
}

containerd_running() {
    [ -S "$CONTAINERD_SOCK" ] || return 1
    command -v ctr >/dev/null 2>&1 || return 0
    ctr --address "$CONTAINERD_SOCK" version >/dev/null 2>&1
}

stop_containerd() {
    if [ -f "$CONTAINERD_PIDFILE" ]; then
        local pid
        pid="$(cat "$CONTAINERD_PIDFILE" 2>/dev/null || true)"
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            log "stopping containerd pid $pid"
            kill "$pid" 2>/dev/null || true
            sleep 2
            kill -9 "$pid" 2>/dev/null || true
        fi
        rm -f "$CONTAINERD_PIDFILE"
    fi
}

start_containerd() {
    local i=0

    [ "$DOCKER_EXTERNAL_CONTAINERD" = "1" ] || return 0
    command -v containerd >/dev/null 2>&1 || {
        log "containerd binary not found; using Docker embedded containerd"
        return 0
    }

    if containerd_running; then
        log "external containerd is already running"
        return 0
    fi

    mkdir -p "$CONTAINERD_ROOT" "$CONTAINERD_STATE" "$(dirname "$CONTAINERD_CONFIG")"
    write_containerd_config || {
        log "failed to write external containerd config"
        return 1
    }

    : > "$CONTAINERD_LOG"
    log "starting external containerd with disabled optional snapshotters"
    containerd \
        --config "$CONTAINERD_CONFIG" \
        --address "$CONTAINERD_SOCK" \
        --root "$CONTAINERD_ROOT" \
        --state "$CONTAINERD_STATE" \
        --log-level debug >> "$CONTAINERD_LOG" 2>&1 &
    echo "$!" > "$CONTAINERD_PIDFILE"

    while [ "$i" -lt "$TEST_TIMEOUT" ]; do
        if containerd_running; then
            log "external containerd is ready"
            log_containerd_state
            return 0
        fi
        if ! kill -0 "$(cat "$CONTAINERD_PIDFILE")" 2>/dev/null; then
            log "external containerd exited early"
            tail -80 "$CONTAINERD_LOG" || true
            rm -f "$CONTAINERD_PIDFILE"
            return 1
        fi
        i=$((i + 1))
        sleep 1
    done

    log "external containerd did not become ready"
    tail -80 "$CONTAINERD_LOG" || true
    stop_containerd
    return 1
}

log_containerd_state() {
    local sock="/var/run/docker/containerd/containerd.sock"

    if [ -S "$CONTAINERD_SOCK" ]; then
        sock="$CONTAINERD_SOCK"
    fi

    [ -S "$sock" ] || {
        log "containerd socket is not present: $sock"
        return 0
    }

    if command -v ctr >/dev/null 2>&1; then
        log "containerd plugins from $sock:"
        ctr --address "$sock" plugins ls 2>&1 | \
            grep -E 'TYPE|lease|content|metadata|snapshot|image|runtime|error|WARN|ERRO' || true
    else
        log "ctr is not installed; skipping embedded containerd plugin list"
    fi
}

start_dockerd_once() {
    local driver="$1"
    local net_mode="$2"
    local args=()
    local dns

    args+=(
        --host=unix:///var/run/docker.sock
        --data-root="$DOCKER_DATA_ROOT"
        --exec-opt native.cgroupdriver=cgroupfs
        "--storage-driver=$driver"
        --debug
    )

    if dockerd_supports_feature_flag; then
        args+=("--feature=containerd-snapshotter=$(dockerd_containerd_snapshotter_value)")
    fi

    if [ "$DOCKER_EXTERNAL_CONTAINERD" = "1" ] && [ -S "$CONTAINERD_SOCK" ]; then
        args+=("--containerd=$CONTAINERD_SOCK")
    fi

    if [ "$DOCKER_RUNC_WRAPPER" = "1" ]; then
        args+=(
            "--add-runtime=nethunter-runc=$RUNC_WRAPPER_PATH"
            --default-runtime=nethunter-runc
        )
    fi

    for dns in $DOCKER_DNS; do
        args+=("--dns=$dns")
    done

    if [ "$net_mode" = "manual-nat" ]; then
        args+=(
            --iptables=false
            --ip-masq=false
            --ip-forward=false
            "--bip=$DOCKER_BRIDGE_CIDR"
        )
    else
        args+=(
            --iptables=true
            --ip-forward=true
        )
    fi

    : > "$DOCKER_LOG"
    log "starting dockerd with storage driver: $driver, network mode: $net_mode"
    if dockerd_supports_feature_flag; then
        log "Docker containerd snapshotter feature: $(dockerd_containerd_snapshotter_value)"
    fi
    if [ "$DOCKER_RUNC_WRAPPER" = "1" ]; then
        log "Docker default runtime: nethunter-runc ($RUNC_WRAPPER_PATH)"
    fi

    dockerd "${args[@]}" >> "$DOCKER_LOG" 2>&1 &

    echo "$!" > "$DOCKER_PIDFILE"

    local i=0
    while [ "$i" -lt "$TEST_TIMEOUT" ]; do
        if dockerd_running; then
            if [ "$net_mode" = "manual-nat" ]; then
                setup_manual_nat || {
                    log "manual NAT setup failed"
                    stop_dockerd
                    return 1
                }
            fi
            log "dockerd is ready"
            return 0
        fi
        if ! kill -0 "$(cat "$DOCKER_PIDFILE")" 2>/dev/null; then
            log "dockerd exited early with $driver, network mode: $net_mode"
            tail -80 "$DOCKER_LOG" || true
            rm -f "$DOCKER_PIDFILE"
            return 1
        fi
        i=$((i + 1))
        sleep 1
    done

    log "dockerd did not become ready with $driver, network mode: $net_mode"
    tail -80 "$DOCKER_LOG" || true
    stop_dockerd
    return 1
}

start_dockerd_with_driver() {
    local driver="$1"

    start_dockerd_once "$driver" docker-iptables && return 0

    if grep -q "failed to create FILTER chain DOCKER\\|iptables failed" "$DOCKER_LOG"; then
        log "Docker-managed iptables failed; retrying $driver with manual NAT"
    else
        log "retrying $driver with manual NAT"
    fi

    start_dockerd_once "$driver" manual-nat && return 0
    return 1
}

start_dockerd() {
    require_root
    unset LD_PRELOAD
    ensure_basic_mounts
    mount_cgroups
    mkdir -p "$DOCKER_DATA_ROOT" /var/run /run
    prepare_mount_propagation

    if dockerd_running; then
        if [ "$DOCKER_KILL_EXISTING" = "1" ]; then
            log "dockerd is already running; restarting it for a clean NetHunter test runtime"
            clear_stale_runtime
        else
            log "dockerd is already running"
            return 0
        fi
    fi

    command -v dockerd >/dev/null 2>&1 || die "dockerd not found; run '$SCRIPT_NAME setup' first"
    clear_stale_runtime
    start_containerd || die "failed to start external containerd"
    write_runc_wrapper || die "failed to install runc wrapper"

    if [ "$DOCKER_STORAGE_DRIVER" = "auto" ]; then
        if dockerd_containerd_snapshotter_enabled; then
            start_dockerd_with_driver overlayfs && return 0
            start_dockerd_with_driver native && return 0
        fi
        start_dockerd_with_driver overlay2 && return 0
        command -v fuse-overlayfs >/dev/null 2>&1 && start_dockerd_with_driver fuse-overlayfs && return 0
        start_dockerd_with_driver vfs && return 0
        die "failed to start dockerd with overlayfs, native, overlay2, fuse-overlayfs, and vfs"
    fi

    start_dockerd_with_driver "$DOCKER_STORAGE_DRIVER"
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

run_docker() {
    log "+ $*"
    "$@" && return 0

    if [ -s "$RUNC_WRAPPER_LOG" ]; then
        log "runc wrapper log:"
        tail -40 "$RUNC_WRAPPER_LOG" || true
    fi

    die "command failed: $*"
}

docker_test() {
    require_root
    unset LD_PRELOAD
    dockerd_running || die "dockerd is not running; run '$SCRIPT_NAME start' first"

    run docker version
    run docker info
    log_containerd_state
    run_docker docker pull alpine
    run_docker docker run --rm alpine uname -a

    # Bridge networking: container gets an IP and default route, but internet
    # access may be blocked by Android's tetherctrl_FORWARD DROP rule.
    log "bridge network test (internet may fail on Android kernels):"
    docker run --rm alpine sh -c 'ip addr; ip route; wget -T 10 -qO- http://example.com >/dev/null && echo internet-ok || echo "(internet blocked by kernel)"' 2>&1 || true

    # Host networking works around the Android iptables restriction
    log "host network internet test:"
    docker run --rm --network host alpine sh -c 'wget -T 10 -qO- http://example.com | head -5' 2>&1 || log "host network internet test skipped"

    docker network rm "$TEST_NETWORK" >/dev/null 2>&1 || true
    run_docker docker network create "$TEST_NETWORK"
    log "custom bridge network test (internet may fail on Android kernels):"
    docker run --rm --network "$TEST_NETWORK" alpine sh -c 'ip addr; ip route; wget -T 10 -qO- http://example.com >/dev/null && echo custom-network-internet-ok || echo "(internet blocked by kernel)"' 2>&1 || true
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
    stop_containerd
    cleanup_manual_nat
    clear_stale_runtime
    log "cleanup done"
}

purge() {
    cleanup
    log "deleting Docker data root: $DOCKER_DATA_ROOT"
    rm -rf "$DOCKER_DATA_ROOT"
    rm -rf "$CONTAINERD_ROOT" "$CONTAINERD_STATE" /var/lib/containerd /run/containerd /var/run/containerd
    rm -f "$CONTAINERD_CONFIG" "$CONTAINERD_LOG"
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
    if iptables_filter_works; then
        log "iptables filter table can create chains"
    else
        log "iptables filter table cannot create chains"
    fi
    command -v iptables >/dev/null 2>&1 && iptables -t nat -S POSTROUTING 2>/dev/null | grep -E 'MASQUERADE|docker|172\\.' || true
    [ -r /proc/sys/net/ipv4/ip_forward ] && printf 'net.ipv4.ip_forward=%s\n' "$(cat /proc/sys/net/ipv4/ip_forward)" || true
    command -v ip >/dev/null 2>&1 && ip route || true
    command -v ps >/dev/null 2>&1 && ps -eo pid=,args= 2>/dev/null | grep -E 'dockerd|containerd' | grep -v grep || true
    log_containerd_state
    [ -s "$RUNC_WRAPPER_LOG" ] && {
        log "runc wrapper log:"
        tail -40 "$RUNC_WRAPPER_LOG" || true
    }
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
maybe_reexec_mount_namespace "$@"

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
