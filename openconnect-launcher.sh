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
