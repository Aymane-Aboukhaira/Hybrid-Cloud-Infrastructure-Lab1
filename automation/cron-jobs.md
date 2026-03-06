# Cron Jobs Reference

## EC2 (root crontab — `sudo crontab -l`)

```
*/5 * * * * /usr/local/bin/update-sg-ip.sh > /dev/null 2>&1
0 2 * * * /usr/local/bin/s3-backup.sh
```

| Schedule | Script | Purpose |
|---|---|---|
| Every 5 min | `update-sg-ip.sh` | Detect home IP change, update AWS SG + Fail2ban |
| Daily 2AM | `s3-backup.sh` | Backup /opt, /etc/fail2ban, /etc/ipsec.* to S3 |

**Log files:**
- `/var/log/update-sg-ip.log` — IP change detection history
- `/var/log/s3-backup.log` — backup upload status

---

## centos-vm2 (root crontab)

```
*/5 * * * * curl -s "https://www.duckdns.org/update?domains=aymane-lab&token=TOKEN&ip=" > /dev/null
0 3 * * * /usr/local/bin/onprem-s3-backup.sh
```

| Schedule | Command | Purpose |
|---|---|---|
| Every 5 min | `curl duckdns.org/update` | Push current home IP to DuckDNS |
| Daily 3AM | `onprem-s3-backup.sh` | Pull configs from all on-prem nodes, upload to S3 |

**Log files:**
- `/var/log/onprem-s3-backup.log` — on-prem backup status

---

## Backup Schedule Timeline

```
00:00 ─────────────────────────────────────────────────────── 23:59
  │                    │                    │
 2:00               3:00               */5min
  │                    │                    │
EC2 backup         On-Prem backup      IP sync check
(NPM/Guacamole/    (pfSense/CentOS/    (DuckDNS →
 IPsec/Fail2ban)    Monitoring stack)   SG + Fail2ban)
  → S3 Tier 2        → S3 Tier 3
```

---

## Verifying Cron is Running

```bash
# Check cron service
systemctl status cron        # Debian/Ubuntu
systemctl status crond       # CentOS/RHEL

# View recent cron execution log
grep CRON /var/log/syslog | tail -20   # Ubuntu
grep cron /var/log/cron | tail -20     # CentOS

# Manually test a script
sudo /usr/local/bin/update-sg-ip.sh
sudo /usr/local/bin/s3-backup.sh
sudo /usr/local/bin/onprem-s3-backup.sh
```
