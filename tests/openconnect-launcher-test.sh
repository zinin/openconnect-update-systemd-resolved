#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

TEST_TMPDIR=$(mktemp -d)
cleanup() {
    if [ -f "$TEST_TMPDIR/mock-openconnect.pid" ]; then
        mock_pid=$(cat "$TEST_TMPDIR/mock-openconnect.pid" 2>/dev/null || true)
        if [ -n "${mock_pid:-}" ] && kill -0 "$mock_pid" 2>/dev/null; then
            kill "$mock_pid" 2>/dev/null || true
            wait "$mock_pid" 2>/dev/null || true
        fi
    fi
    rm -rf "$TEST_TMPDIR"
}
trap cleanup EXIT

assert_file_missing() {
    local path="$1"
    local message="$2"
    if [ -e "$path" ]; then
        echo "ASSERTION FAILED: $message" >&2
        exit 1
    fi
}

assert_pid_alive() {
    local pid_file="$1"
    local message="$2"
    if [ ! -f "$pid_file" ]; then
        echo "ASSERTION FAILED: missing pid file: $pid_file" >&2
        exit 1
    fi

    local pid
    pid=$(cat "$pid_file")
    if ! kill -0 "$pid" 2>/dev/null; then
        echo "ASSERTION FAILED: $message" >&2
        exit 1
    fi
}

prepare_fixtures() {
    local bin_dir="$TEST_TMPDIR/bin"
    mkdir -p "$bin_dir"

    cat > "$bin_dir/ip" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

marker="${MOCK_VPN_UP:?}"

if [ "${1:-}" = "addr" ] && [ "${2:-}" = "show" ] && [ -f "$marker" ]; then
    printf '3: %s: <POINTOPOINT,MULTICAST,NOARP,UP,LOWER_UP>\n' "${3:-tun-test}"
    printf '    inet 10.66.77.88/24 scope global %s\n' "${3:-tun-test}"
    exit 0
fi

exit 1
EOF
    chmod +x "$bin_dir/ip"

    cat > "$bin_dir/mock-openconnect" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

marker="${MOCK_VPN_UP:?}"
pid_file="${MOCK_OPENCONNECT_PIDFILE:?}"

echo $$ > "$pid_file"
touch "$marker"
sleep 10
EOF
    chmod +x "$bin_dir/mock-openconnect"
}

prepare_script_copy() {
    local config_file="$TEST_TMPDIR/openconnect.conf"
    local log_file="$TEST_TMPDIR/openconnect-launcher.log"
    local script_copy="$TEST_TMPDIR/openconnect-launcher.sh"

    sed \
        -e "s|^readonly CONFIG_FILE=.*$|readonly CONFIG_FILE=\"$config_file\"|" \
        -e "s|^readonly LOG_FILE=.*$|readonly LOG_FILE=\"$log_file\"|" \
        "$ROOT_DIR/openconnect-launcher.sh" > "$script_copy"
    chmod +x "$script_copy"

    cat > "$config_file" <<EOF
VPN_USER="user"
VPN_PASSWORD='password'
VPN_SERVER="vpn.example.test"
VPN_INTERFACE="tun-test"
VPN_SCRIPT="/bin/true"
VPN_TEST_URL=""
LOCK_FILE="$TEST_TMPDIR/openconnect.lock"
LOCK_TIMEOUT=300
DAEMON_MODE=true
OPENCONNECT_BIN="$TEST_TMPDIR/bin/mock-openconnect"
EOF

    echo "$script_copy"
}

test_daemon_mode_detaches_from_openconnect() {
    prepare_fixtures

    local script_copy
    script_copy=$(prepare_script_copy)

    export PATH="$TEST_TMPDIR/bin:$PATH"
    export MOCK_VPN_UP="$TEST_TMPDIR/mock-vpn-up"
    export MOCK_OPENCONNECT_PIDFILE="$TEST_TMPDIR/mock-openconnect.pid"

    if ! timeout 2 "$script_copy"; then
        echo "ASSERTION FAILED: launcher did not exit promptly in daemon mode" >&2
        exit 1
    fi

    assert_pid_alive \
        "$TEST_TMPDIR/mock-openconnect.pid" \
        "mock openconnect should keep running after launcher exits"

    assert_file_missing \
        "$TEST_TMPDIR/openconnect.lock" \
        "launcher should release lock after successful daemon startup"
}

test_daemon_mode_detaches_from_openconnect
echo "PASS: openconnect-launcher daemon mode detaches cleanly"
