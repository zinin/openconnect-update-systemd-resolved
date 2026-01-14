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
