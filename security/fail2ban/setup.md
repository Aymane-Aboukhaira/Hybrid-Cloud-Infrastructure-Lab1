# Fail2ban Setup

## Why Fail2ban in a Containerized Environment is Non-Trivial

Three architectural challenges must be solved:

### Challenge 1: Log Blindspot
Guacamole runs inside Docker. Its logs go to Docker's json-file driver (`docker logs guacamole`), not to any file on the host. Fail2ban cannot read them.

**Solution**: Read Nginx Proxy Manager's access logs instead. NPM logs all requests including the real client IP (extracted from X-Forwarded-For). Path: `/opt/npm/data/logs/proxy-host-*_access.log`

### Challenge 2: Docker Firewall Bypass
Docker manages its own iptables rules. Rules added to the INPUT chain are bypassed because Docker routes container traffic through FORWARD, not INPUT.

**Solution**: Inject bans into the `DOCKER-USER` chain. This is the only chain that Docker explicitly checks before its own rules. Fail2ban must use:
```
chain = DOCKER-USER
```

### Challenge 3: Admin Self-Lockout
Home network (admin workstation) and pfSense share the same public IP via residential NAT. If Fail2ban bans that IP, it drops UDP 500/4500 (IPsec) and collapses the VPN tunnel — simultaneously locking out SSH and Guacamole.

**Solution**: Always whitelist the home IP in `ignoreip`. This is auto-updated by `update-sg-ip.sh` when the dynamic home IP changes.

---

## Installation

```bash
sudo apt install -y fail2ban
```

## NPM Log Filter

Create `/etc/fail2ban/filter.d/npm-general.conf`:
```ini
[Definition]
failregex = .* (403|404) \d+ - .* \[Client <HOST>\].*
ignoreregex =
```

This regex matches 403 (forbidden) and 404 (not found) errors from NPM logs, catching both credential stuffers and vulnerability scanners.

## Verification

```bash
# Check all jail status
sudo fail2ban-client status

# Check specific jail
sudo fail2ban-client status npm-docker

# View DOCKER-USER chain to confirm bans are inserted correctly
sudo iptables -n -L DOCKER-USER

# Manually unban an IP
sudo fail2ban-client set npm-docker unbanip 1.2.3.4

# Test the filter against a log file
fail2ban-regex /opt/npm/data/logs/proxy-host-1_access.log /etc/fail2ban/filter.d/npm-general.conf
```

## Live Test

To verify the jail works end-to-end:
1. Generate 5 HTTP 404 requests to `https://guac.51.20.237.223.nip.io/nonexistent` **from a non-whitelisted IP**
2. Check `sudo fail2ban-client status npm-docker` — banned IPs list should update
3. Verify: `sudo iptables -n -L DOCKER-USER | grep <IP>`
