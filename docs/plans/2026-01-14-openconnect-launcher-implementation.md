# OpenConnect Launcher Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Добавить скрипт автозапуска VPN с поддержкой 2FA и cron, унифицировать конфигурацию в один файл.

**Architecture:** Единый конфиг `/usr/local/etc/openconnect.conf` используется обоими скриптами. Launcher управляет жизненным циклом VPN-соединения с lock-файлом для защиты от race conditions при 2FA. Systemd-resolved скрипт читает дополнительные домены из того же конфига.

**Tech Stack:** Bash, systemd-resolved (busctl), openconnect

---

## Task 1: Создать пример конфига

**Files:**
- Create: `openconnect.conf.example`

**Step 1: Создать файл примера конфига**

```bash
# OpenConnect VPN Configuration
# Copy to /usr/local/etc/openconnect.conf and edit
# Permissions: chmod 600 /usr/local/etc/openconnect.conf

# === Credentials (required) ===
VPN_USER="username"
VPN_PASSWORD='your-password-here'  # use single quotes for special chars
VPN_SERVER="vpn.example.com"
VPN_AUTHGROUP=""  # optional, e.g. "VPN-2FA"

# === Interface settings ===
VPN_INTERFACE="tun0"
VPN_SCRIPT="/usr/local/bin/openconnect-update-systemd-resolved"

# === Connection verification (optional) ===
# URL to check if VPN is working (leave empty to skip check)
VPN_TEST_URL=""  # e.g. "https://internal.example.com/"
MAX_ATTEMPTS=3
RETRY_DELAY=3

# === Lock file settings ===
LOCK_FILE="/var/run/openconnect-launcher.lock"
LOCK_TIMEOUT=300  # seconds, how long to wait for 2FA

# === Run mode ===
# true: run openconnect in background (for cron)
# false: run interactively (for manual start)
DAEMON_MODE=false

# === Extra DNS domains (optional) ===
# Space-separated list of additional domains to resolve through VPN DNS
# Example: "example.com corp.example.com internal.example.com"
EXTRA_DNS_DOMAINS=""
```

**Step 2: Проверить синтаксис**

Run: `bash -n openconnect.conf.example`
Expected: No output (success)

**Step 3: Commit**

```bash
git add openconnect.conf.example
git commit -m "feat: add example configuration file"
```

---

## Task 2: Обновить openconnect-update-systemd-resolved

**Files:**
- Modify: `openconnect-update-systemd-resolved:7` (константа EXTRA_DOMAINS_FILE)
- Modify: `openconnect-update-systemd-resolved:192-203` (загрузка доменов)

**Step 1: Заменить константу EXTRA_DOMAINS_FILE на CONFIG_FILE**

Строка 7, заменить:
```bash
EXTRA_DOMAINS_FILE="/usr/local/etc/openconnect-extra-domains.conf"
```

На:
```bash
CONFIG_FILE="/usr/local/etc/openconnect.conf"
```

**Step 2: Заменить логику загрузки дополнительных доменов**

Строки 192-203, заменить:
```bash
    # Add extra domains from config file
    if [ -f "$EXTRA_DOMAINS_FILE" ]; then
        while IFS= read -r extra_domain || [ -n "$extra_domain" ]; do
            # Skip empty lines and comments
            extra_domain=$(echo "$extra_domain" | sed 's/#.*//' | tr -d '[:space:]')
            if [ -n "$extra_domain" ]; then
                all_domains="$all_domains \"$extra_domain\" false"
                domain_count=$((domain_count + 1))
                log "INFO: Adding extra domain: $extra_domain"
            fi
        done < "$EXTRA_DOMAINS_FILE"
    fi
```

На:
```bash
    # Add extra domains from config file
    if [ -f "$CONFIG_FILE" ]; then
        # shellcheck source=/dev/null
        source "$CONFIG_FILE"
        if [ -n "$EXTRA_DNS_DOMAINS" ]; then
            for extra_domain in $EXTRA_DNS_DOMAINS; do
                all_domains="$all_domains \"$extra_domain\" false"
                domain_count=$((domain_count + 1))
                log "INFO: Adding extra domain: $extra_domain"
            done
        fi
    else
        log "WARNING: Config file $CONFIG_FILE not found, no extra domains added"
    fi
```

**Step 3: Проверить синтаксис**

Run: `bash -n openconnect-update-systemd-resolved`
Expected: No output (success)

**Step 4: Commit**

```bash
git add openconnect-update-systemd-resolved
git commit -m "refactor: switch to unified config file for extra DNS domains"
```

---

## Task 3: Создать openconnect-launcher.sh - базовая структура

**Files:**
- Create: `openconnect-launcher.sh`

**Step 1: Создать скрипт с shebang, константами и функцией логирования**

```bash
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
```

**Step 2: Проверить синтаксис**

Run: `bash -n openconnect-launcher.sh`
Expected: No output (success)

**Step 3: Commit**

```bash
git add openconnect-launcher.sh
git commit -m "feat(launcher): add base structure with logging"
```

---

## Task 4: Добавить загрузку конфига

**Files:**
- Modify: `openconnect-launcher.sh`

**Step 1: Добавить функцию загрузки конфига и значения по умолчанию**

Добавить после функций логирования:

```bash
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
```

**Step 2: Проверить синтаксис**

Run: `bash -n openconnect-launcher.sh`
Expected: No output (success)

**Step 3: Commit**

```bash
git add openconnect-launcher.sh
git commit -m "feat(launcher): add config loading with validation"
```

---

## Task 5: Добавить управление lock-файлом

**Files:**
- Modify: `openconnect-launcher.sh`

**Step 1: Добавить функции работы с lock-файлом**

Добавить после load_config:

```bash
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
```

**Step 2: Проверить синтаксис**

Run: `bash -n openconnect-launcher.sh`
Expected: No output (success)

**Step 3: Commit**

```bash
git add openconnect-launcher.sh
git commit -m "feat(launcher): add lock file management with timeout"
```

---

## Task 6: Добавить проверку состояния VPN

**Files:**
- Modify: `openconnect-launcher.sh`

**Step 1: Добавить функции проверки VPN**

Добавить после функций lock:

```bash
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
```

**Step 2: Проверить синтаксис**

Run: `bash -n openconnect-launcher.sh`
Expected: No output (success)

**Step 3: Commit**

```bash
git add openconnect-launcher.sh
git commit -m "feat(launcher): add VPN status checking functions"
```

---

## Task 7: Добавить запуск openconnect

**Files:**
- Modify: `openconnect-launcher.sh`

**Step 1: Добавить функцию запуска openconnect**

Добавить после check функций:

```bash
# Start openconnect
start_openconnect() {
    local cmd="openconnect"
    cmd="$cmd -i $VPN_INTERFACE"
    cmd="$cmd --script=$VPN_SCRIPT"
    cmd="$cmd -u $VPN_USER"

    if [ -n "$VPN_AUTHGROUP" ]; then
        cmd="$cmd --authgroup=\"$VPN_AUTHGROUP\""
    fi

    if [ "$DAEMON_MODE" = "true" ]; then
        cmd="$cmd --background"
    fi

    cmd="$cmd $VPN_SERVER"

    log_info "Starting openconnect: $cmd"

    # Run openconnect with password on stdin
    if [ "$DAEMON_MODE" = "true" ]; then
        echo "$VPN_PASSWORD" | eval "$cmd"
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
        echo "$VPN_PASSWORD" | eval "$cmd"
        return $?
    fi
}
```

**Step 2: Проверить синтаксис**

Run: `bash -n openconnect-launcher.sh`
Expected: No output (success)

**Step 3: Commit**

```bash
git add openconnect-launcher.sh
git commit -m "feat(launcher): add openconnect startup function"
```

---

## Task 8: Добавить главную функцию

**Files:**
- Modify: `openconnect-launcher.sh`

**Step 1: Добавить main функцию и точку входа**

Добавить в конец файла:

```bash
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
    local vpn_status
    check_vpn_status
    vpn_status=$?

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
```

**Step 2: Проверить синтаксис**

Run: `bash -n openconnect-launcher.sh`
Expected: No output (success)

**Step 3: Сделать скрипт исполняемым**

Run: `chmod +x openconnect-launcher.sh`

**Step 4: Commit**

```bash
git add openconnect-launcher.sh
git commit -m "feat(launcher): add main function and entry point"
```

---

## Task 9: Обновить README

**Files:**
- Modify: `README.md`

**Step 1: Добавить секцию про launcher после секции "Extra DNS Domains"**

Добавить после строки 68 (после секции Extra DNS Domains):

```markdown
### VPN Launcher Script

For automated VPN management with 2FA support, use the `openconnect-launcher.sh` script:

1. Copy and configure:
   ```bash
   sudo cp openconnect.conf.example /usr/local/etc/openconnect.conf
   sudo chmod 600 /usr/local/etc/openconnect.conf
   sudo nano /usr/local/etc/openconnect.conf  # fill in your credentials
   ```

2. Install the launcher:
   ```bash
   sudo cp openconnect-launcher.sh /usr/local/bin/
   sudo chmod +x /usr/local/bin/openconnect-launcher.sh
   ```

3. Run manually:
   ```bash
   sudo /usr/local/bin/openconnect-launcher.sh
   ```

4. Or set up cron for automatic reconnection:
   ```bash
   echo "* * * * * root /usr/local/bin/openconnect-launcher.sh" | sudo tee /etc/cron.d/openconnect-vpn
   ```

The launcher handles:
- Checking if VPN is already connected
- Preventing duplicate connections during 2FA authentication
- Automatic reconnection if VPN drops
- Lock file with configurable timeout for 2FA wait

Set `DAEMON_MODE=true` in config for cron usage.
```

**Step 2: Обновить секцию про конфигурацию**

Заменить строки 49-68 (секция Extra DNS Domains) на:

```markdown
### Configuration

All settings are stored in `/usr/local/etc/openconnect.conf`. Create it from the example:

```bash
sudo cp openconnect.conf.example /usr/local/etc/openconnect.conf
sudo chmod 600 /usr/local/etc/openconnect.conf
```

The config file uses shell variable syntax. See `openconnect.conf.example` for all available options.

**Extra DNS Domains:** If your VPN provides a subdomain (e.g., `subdomain.example.com`) but you need to resolve all `*.example.com` hosts through VPN DNS, add them to `EXTRA_DNS_DOMAINS` in the config:

```bash
EXTRA_DNS_DOMAINS="example.com corp.example.com"
```
```

**Step 3: Commit**

```bash
git add README.md
git commit -m "docs: update README with launcher instructions and new config format"
```

---

## Task 10: Финальная проверка

**Step 1: Проверить все файлы shellcheck**

Run: `shellcheck openconnect-launcher.sh openconnect-update-systemd-resolved || true`
Expected: Review warnings, fix critical issues if any

**Step 2: Проверить структуру репозитория**

Run: `ls -la`
Expected: See all new files

**Step 3: Просмотреть историю коммитов**

Run: `git log --oneline -10`
Expected: See all new commits

**Step 4: Удалить старый конфиг-файл из документации (если упоминается)**

Review README.md for any remaining references to `openconnect-extra-domains.conf` and remove them.

---

## Summary

После выполнения плана будут созданы:
- `openconnect.conf.example` — пример конфига
- `openconnect-launcher.sh` — скрипт автозапуска VPN
- Обновлённый `openconnect-update-systemd-resolved` — с поддержкой нового конфига
- Обновлённый `README.md` — с инструкциями

Коммиты: ~9 атомарных коммитов с осмысленными сообщениями.
