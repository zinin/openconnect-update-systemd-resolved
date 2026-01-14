#!/bin/bash

# OpenConnect VPN Launcher
# Manages VPN connection lifecycle with 2FA support

set -euo pipefail

# Constants
readonly CONFIG_FILE="/usr/local/etc/openconnect.conf"
readonly LOG_FILE="/var/log/openconnect-launcher.log"

# Exit codes
readonly EXIT_OK=0
readonly EXIT_CONFIG_ERROR=1
readonly EXIT_WAITING_2FA=2
readonly EXIT_CONNECTION_ERROR=3

# Lock state
LOCK_ACQUIRED=false

# Logging
log() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "$timestamp - $level - $message" >> "$LOG_FILE"
    if [ "${DAEMON_MODE:-false}" != "true" ]; then
        echo "$timestamp - $level - $message"
    fi
}

log_info() { log "INFO" "$1"; }
log_warn() { log "WARN" "$1"; }
log_error() { log "ERROR" "$1"; }

# Load configuration
load_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        log_error "Config file not found: $CONFIG_FILE"
        return 1
    fi

    # shellcheck source=/dev/null
    source "$CONFIG_FILE"

    # Validate required fields
    if [ -z "${VPN_USER:-}" ]; then
        log_error "VPN_USER is not set in config"
        return 1
    fi
    if [ -z "${VPN_PASSWORD:-}" ]; then
        log_error "VPN_PASSWORD is not set in config"
        return 1
    fi
    if [ -z "${VPN_SERVER:-}" ]; then
        log_error "VPN_SERVER is not set in config"
        return 1
    fi

    # Set defaults
    VPN_INTERFACE="${VPN_INTERFACE:-tun0}"
    VPN_SCRIPT="${VPN_SCRIPT:-/usr/local/bin/openconnect-update-systemd-resolved}"
    VPN_TEST_URL="${VPN_TEST_URL:-}"
    VPN_AUTHGROUP="${VPN_AUTHGROUP:-}"
    MAX_ATTEMPTS="${MAX_ATTEMPTS:-3}"
    RETRY_DELAY="${RETRY_DELAY:-3}"
    LOCK_FILE="${LOCK_FILE:-/var/run/openconnect-launcher.lock}"
    LOCK_TIMEOUT="${LOCK_TIMEOUT:-300}"
    DAEMON_MODE="${DAEMON_MODE:-false}"

    log_info "Config loaded successfully"
    return 0
}

# Check if lock file is stale
is_lock_stale() {
    local lock_file="$1"
    local timeout="$2"

    if [ ! -f "$lock_file" ]; then
        return 0  # No lock = stale (can proceed)
    fi

    # Check if PID in lock is still alive
    local pid
    pid=$(cat "$lock_file" 2>/dev/null || echo "")
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        # Process alive, check timeout
        local lock_age
        lock_age=$(( $(date +%s) - $(stat -c %Y "$lock_file") ))
        if [ "$lock_age" -lt "$timeout" ]; then
            return 1  # Lock is fresh and process alive
        fi
        log_warn "Lock file older than ${timeout}s, considering stale"
    fi

    return 0  # Lock is stale
}

# Acquire lock (uses flock for atomicity if available)
acquire_lock() {
    local lock_file="$1"

    # Check for stale lock first
    if ! is_lock_stale "$lock_file" "$LOCK_TIMEOUT"; then
        local pid
        pid=$(cat "$lock_file" 2>/dev/null || echo "unknown")
        log_info "Another instance running (PID: $pid), waiting for 2FA"
        return 1
    fi

    # Try to use flock for atomic lock acquisition
    if command -v flock >/dev/null 2>&1; then
        exec 200>"$lock_file"
        if ! flock -n 200; then
            log_info "Another instance acquired lock, waiting for 2FA"
            return 1
        fi
    else
        # Fallback: remove stale lock if exists
        rm -f "$lock_file"
    fi

    # Write our PID to lock file
    echo $$ > "$lock_file"
    LOCK_ACQUIRED=true
    log_info "Lock acquired (PID: $$)"
    return 0
}

# Release lock
release_lock() {
    local lock_file="$1"
    if [ -f "$lock_file" ]; then
        rm -f "$lock_file"
        log_info "Lock released"
    fi
}

# Cleanup on exit (called via trap)
# shellcheck disable=SC2317
cleanup() {
    if [ "$LOCK_ACQUIRED" = "true" ]; then
        release_lock "$LOCK_FILE"
    fi
}

# Check if interface has IP
interface_has_ip() {
    local iface="$1"
    ip addr show "$iface" 2>/dev/null | grep -q "inet "
}

# Check if internal resource is accessible
check_internal_resource() {
    local url="$1"
    local max_attempts="$2"
    local retry_delay="$3"

    if [ -z "$url" ]; then
        return 0  # No URL configured, assume OK
    fi

    local attempt=1
    while [ "$attempt" -le "$max_attempts" ]; do
        if curl -s -k -m 10 -o /dev/null -w "%{http_code}" "$url" | grep -q -E "^(200|302)$"; then
            return 0
        fi
        if [ "$attempt" -lt "$max_attempts" ]; then
            sleep "$retry_delay"
        fi
        attempt=$((attempt + 1))
    done

    return 1
}

# Check VPN status
check_vpn_status() {
    if interface_has_ip "$VPN_INTERFACE"; then
        if check_internal_resource "$VPN_TEST_URL" "$MAX_ATTEMPTS" "$RETRY_DELAY"; then
            log_info "VPN is connected and working"
            return 0  # VPN OK
        else
            log_warn "VPN interface has IP but internal resources not accessible"
            return 2  # Need reconnect
        fi
    fi
    return 1  # No VPN
}

# Kill existing openconnect process
kill_openconnect() {
    if pgrep -f "openconnect.*$VPN_INTERFACE" >/dev/null; then
        log_info "Terminating existing openconnect process"
        pkill -f "openconnect.*$VPN_INTERFACE" || true
        sleep 2
    fi
}

# Start openconnect
start_openconnect() {
    local -a cmd=(openconnect -i "$VPN_INTERFACE" "--script=$VPN_SCRIPT" -u "$VPN_USER")

    if [ -n "$VPN_AUTHGROUP" ]; then
        cmd+=("--authgroup=$VPN_AUTHGROUP")
    fi

    if [ "$DAEMON_MODE" = "true" ]; then
        cmd+=(--background)
    fi

    cmd+=("$VPN_SERVER")

    log_info "Starting openconnect to $VPN_SERVER"

    # Run openconnect with password on stdin
    if [ "$DAEMON_MODE" = "true" ]; then
        echo "$VPN_PASSWORD" | "${cmd[@]}"
        local result=$?

        if [ $result -eq 0 ]; then
            # Wait for interface to get IP
            local wait_count=0
            while [ $wait_count -lt 30 ]; do
                if interface_has_ip "$VPN_INTERFACE"; then
                    log_info "VPN connected successfully"
                    return 0
                fi
                sleep 1
                wait_count=$((wait_count + 1))
            done
            log_error "Timeout waiting for VPN interface"
            return 1
        else
            log_error "openconnect failed with exit code: $result"
            return 1
        fi
    else
        # Interactive mode
        echo "$VPN_PASSWORD" | "${cmd[@]}"
        return $?
    fi
}

# Main function
main() {
    # Ensure log file exists
    touch "$LOG_FILE" 2>/dev/null || {
        echo "Cannot write to log file: $LOG_FILE" >&2
        exit $EXIT_CONFIG_ERROR
    }

    log_info "=== OpenConnect Launcher started ==="

    # Load config
    if ! load_config; then
        exit $EXIT_CONFIG_ERROR
    fi

    # Set up cleanup trap
    trap cleanup EXIT

    # Check lock
    if ! acquire_lock "$LOCK_FILE"; then
        exit $EXIT_WAITING_2FA
    fi

    # Check current VPN status
    local vpn_status=0
    check_vpn_status || vpn_status=$?

    case $vpn_status in
        0)
            # VPN working fine
            release_lock "$LOCK_FILE"
            exit $EXIT_OK
            ;;
        2)
            # Need reconnect
            kill_openconnect
            ;;
        *)
            # No VPN, check for orphan process
            kill_openconnect
            ;;
    esac

    # Start VPN
    if start_openconnect; then
        log_info "VPN connection established"
        if [ "$DAEMON_MODE" = "true" ]; then
            release_lock "$LOCK_FILE"
        fi
        exit $EXIT_OK
    else
        log_error "Failed to establish VPN connection"
        exit $EXIT_CONNECTION_ERROR
    fi
}

# Run main
main "$@"
