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
2. Save the script as `openconnect-systemd-helper.sh` (or any name you prefer).
3. Ensure the script is executable:
   ```bash
   chmod +x openconnect-systemd-helper.sh
   ```
4. Place the script in a location accessible to OpenConnect, e.g., `/usr/local/bin/`.

## Usage
This script is triggered by OpenConnect based on the `reason` variable provided in its environment. OpenConnect passes the following phases to the script:

- **pre-init**: Ignored by this script.
- **connect**: Sets up the VPN connection, including routes, DNS, and interface settings.
- **disconnect**: Cleans up the VPN connection, reverting DNS and interface configurations.

### Example OpenConnect Command
To use this script with OpenConnect, specify it as a `script`:

```bash
sudo openconnect --script=/path/to/openconnect-systemd-helper.sh https://vpn.example.com
```

## Logging
All actions and errors are logged to `/var/log/openconnect-systemd.log`. Ensure this file is writable by the script.

## Environment Variables
The script relies on various environment variables set by OpenConnect:

- `TUNDEV`: Name of the tunnel device (e.g., `tun0`).
- `INTERNAL_IP4_ADDRESS`, `INTERNAL_IP4_NETMASK`: IPv4 configuration for the VPN interface.
- `INTERNAL_IP4_MTU`: MTU setting for the VPN interface.
- `INTERNAL_IP6_ADDRESS`, `INTERNAL_IP6_NETMASK`: IPv6 configuration for the VPN interface.
- `X-CSTP-Split-Include`: Comma-separated list of networks to route through the VPN.
- `X-CSTP-Split-Exclude`: Comma-separated list of networks to bypass the VPN.
- `X-CSTP-DNS`: DNS servers to use with the VPN.
- `X-CSTP-Default-Domain`: Default DNS search domain for the VPN.

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
