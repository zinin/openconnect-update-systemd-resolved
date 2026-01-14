# OpenConnect Launcher Design

## Overview

Скрипт `openconnect-launcher.sh` для автоматического запуска и поддержания VPN-соединения через OpenConnect с поддержкой 2FA.

## Файлы

**В репозитории:**
- `openconnect-update-systemd-resolved` — существующий скрипт (обновить)
- `openconnect-launcher.sh` — новый скрипт запуска
- `openconnect.conf.example` — пример конфига

**В системе:**
- `/usr/local/etc/openconnect.conf` — конфиг с credentials
- `/var/run/openconnect-launcher.lock` — lock-файл
- `/var/log/openconnect-launcher.log` — лог

## Конфигурация

Формат: shell-переменные (source). Файл `/usr/local/etc/openconnect.conf`:

```bash
# Credentials (required)
VPN_USER="username"
VPN_PASSWORD='your-password-here'
VPN_SERVER="vpn.example.com"
VPN_AUTHGROUP=""  # optional

# Interface settings
VPN_INTERFACE="tun0"
VPN_SCRIPT="/usr/local/bin/openconnect-update-systemd-resolved"

# Connection verification
VPN_TEST_URL=""  # optional
MAX_ATTEMPTS=3
RETRY_DELAY=3

# Lock file settings
LOCK_TIMEOUT=300  # seconds

# Run mode: true for cron/background, false for interactive
DAEMON_MODE=false

# Extra DNS domains (space-separated, optional)
EXTRA_DNS_DOMAINS=""
```

## Логика openconnect-launcher.sh

```
1. Загрузить конфиг /usr/local/etc/openconnect.conf
   └─ Если нет — ошибка и выход

2. Проверить lock-файл
   ├─ Lock существует?
   │   ├─ PID из lock ещё жив? → выход (ждём 2FA)
   │   └─ PID мёртв или lock старше LOCK_TIMEOUT? → удалить lock
   └─ Нет lock → продолжаем

3. Проверить VPN интерфейс
   ├─ Интерфейс есть и имеет IP?
   │   ├─ Внутренние ресурсы доступны? → выход 0 (всё ок)
   │   └─ Ресурсы недоступны → убить openconnect, продолжить
   └─ Интерфейса нет → продолжаем

4. Проверить запущенный openconnect
   └─ Процесс есть, но интерфейс не работает? → убить

5. Создать lock-файл (записать PID)

6. Запустить openconnect
   ├─ DAEMON_MODE=true → с флагом --background
   └─ DAEMON_MODE=false → на переднем плане

7. После завершения/успеха — удалить lock-файл
```

## Изменения в openconnect-update-systemd-resolved

1. Путь к конфигу: `EXTRA_DOMAINS_FILE` → `CONFIG_FILE="/usr/local/etc/openconnect.conf"`
2. Загрузка доменов: чтение файла построчно → source конфига + разбор `EXTRA_DNS_DOMAINS`
3. Если конфига нет — продолжить без дополнительных доменов (warning в лог)

## Коды выхода openconnect-launcher.sh

- `0` — VPN работает или успешно запущен
- `1` — ошибка конфигурации
- `2` — ожидание 2FA (lock активен)
- `3` — ошибка подключения

## Установка

```bash
# Скопировать скрипты
sudo cp openconnect-update-systemd-resolved /usr/local/bin/
sudo cp openconnect-launcher.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/openconnect-*

# Создать конфиг
sudo cp openconnect.conf.example /usr/local/etc/openconnect.conf
sudo chmod 600 /usr/local/etc/openconnect.conf
sudo nano /usr/local/etc/openconnect.conf

# Для cron (каждую минуту)
echo "* * * * * root /usr/local/bin/openconnect-launcher.sh" | sudo tee /etc/cron.d/openconnect-vpn
```
