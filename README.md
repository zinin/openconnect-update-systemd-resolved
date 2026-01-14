# OpenConnect Systemd Integration Script

## Overview
This Bash script is designed to work as a custom NetworkManager or OpenConnect VPN helper script, primarily used to handle VPN connections established through OpenConnect. It integrates with `systemd-resolved` for DNS management and provides capabilities for managing split tunneling routes and other VPN-related configurations.

This project is based on the work of [jonathanio/update-systemd-resolved](https://github.com/jonathanio/update-systemd-resolved).

## Features
- Configures network interface settings for VPN tunnels.
- Sets up split tunneling routes based on environment variables provided by OpenConnect.
- Handles DNS configuration using `systemd-resolved` via `busctl`.
- Configures IPv6 settings if applicable.
- Supports clean disconnection, including DNS and route cleanup.
- Logs all actions to `/var/log/openconnect-systemd.log`.

## Prerequisites
- A Linux distribution with `systemd` and `busctl` available.
- OpenConnect installed and configured.
- Sufficient permissions to manage network settings (requires root or elevated privileges).

## Installation
1. Clone this repository or copy the script to your system:
   ```bash
   git clone https://github.com/zinin/openconnect-update-systemd-resolved.git
   cd openconnect-update-systemd-resolved
   ```
2. Ensure the script is executable:
   ```bash
   chmod +x openconnect-update-systemd-resolved
   ```
3. Place the script in a location accessible to OpenConnect, e.g., `/usr/local/bin/`.

## Usage
This script is triggered by OpenConnect based on the `reason` variable provided in its environment. OpenConnect passes the following phases to the script:

- **pre-init**: Ignored by this script.
- **connect**: Sets up the VPN connection, including routes, DNS, and interface settings.
- **disconnect**: Cleans up the VPN connection, reverting DNS and interface configurations.

### Example OpenConnect Command
To use this script with OpenConnect, specify it as a `script`:

```bash
sudo openconnect --script=/path/to/openconnect-update-systemd-resolved https://vpn.example.com
```

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
   echo '* * * * * root /usr/local/bin/openconnect-launcher.sh >/dev/null 2>&1' | sudo tee /etc/cron.d/openconnect-vpn
   ```

The launcher handles:
- Checking if VPN is already connected
- Preventing duplicate connections during 2FA authentication
- Automatic reconnection if VPN drops
- Lock file with configurable timeout for 2FA wait

Set `DAEMON_MODE=true` in config for cron usage.

## Logging
All actions and errors are logged to `/var/log/openconnect-systemd.log`. Ensure this file is writable by the script.

## Verifying DNS Configuration
After the script runs, you can verify the DNS settings by running `resolvectl` and checking the output. It should display something like this:

```
Link 45 (tun1)
    Current Scopes: DNS
         Protocols: +DefaultRoute -LLMNR -mDNS -DNSOverTLS DNSSEC=no/unsupported
Current DNS Server: 192.168.1.10
       DNS Servers: 192.168.1.10 192.168.1.20
        DNS Domain: lan.test.com
```

This indicates that the DNS servers and domain have been correctly configured for the VPN interface.

## Environment Variables
The script relies on various environment variables set by OpenConnect:

- `TUNDEV`: Name of the tunnel device (e.g., `tun0`).
- `INTERNAL_IP4_ADDRESS`, `INTERNAL_IP4_NETMASK`: IPv4 configuration for the VPN interface.
- `INTERNAL_IP4_MTU`: MTU setting for the VPN interface.
- `INTERNAL_IP6_ADDRESS`, `INTERNAL_IP6_NETMASK`: IPv6 configuration for the VPN interface.
- `X-CSTP-Split-Include`: Networks to route through the VPN (multiple variables, one per network).
- `X-CSTP-Split-Exclude`: Networks to bypass the VPN (multiple variables, one per network).
- `X-CSTP-DNS`: DNS servers to use with the VPN (multiple variables, one per server).
- `X-CSTP-Default-Domain`: Default DNS search domain for the VPN.

Additionally, extra domains can be configured via `EXTRA_DNS_DOMAINS` in `/usr/local/etc/openconnect.conf` (see "Configuration" section above).

## Limitations
- The script assumes the presence of `systemd-resolved` and may not work on systems without it.
- IPv6 functionality is basic and may require further customization for complex use cases.

## Troubleshooting
- Ensure `busctl` is installed and functional if DNS configuration fails.
- Check `/var/log/openconnect-systemd.log` for detailed error logs and debugging information.

## License
This script is provided under the MIT License. See the `LICENSE` file for details.

## Contributions
Contributions, bug reports, and feature requests are welcome! Please submit them via GitHub Issues or pull requests.
