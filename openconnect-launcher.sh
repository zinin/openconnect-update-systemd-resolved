#!/bin/bash

# OpenConnect VPN Launcher
# Manages VPN connection lifecycle with 2FA support

set -euo pipefail

# Constants
CONFIG_FILE="/usr/local/etc/openconnect.conf"
LOG_FILE="/var/log/openconnect-launcher.log"

# Exit codes
EXIT_OK=0
EXIT_CONFIG_ERROR=1
EXIT_WAITING_2FA=2
EXIT_CONNECTION_ERROR=3

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

# Acquire lock
acquire_lock() {
    local lock_file="$1"

    if ! is_lock_stale "$lock_file" "$LOCK_TIMEOUT"; then
        local pid
        pid=$(cat "$lock_file" 2>/dev/null || echo "unknown")
        log_info "Another instance running (PID: $pid), waiting for 2FA"
        return 1
    fi

    # Remove stale lock if exists
    rm -f "$lock_file"

    # Create new lock with our PID
    echo $$ > "$lock_file"
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

# Cleanup on exit
cleanup() {
    release_lock "$LOCK_FILE"
}
