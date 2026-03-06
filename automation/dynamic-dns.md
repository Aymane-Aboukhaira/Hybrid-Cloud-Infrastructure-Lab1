# Dynamic DNS & Self-Healing IP Automation

## Problem Statement

Residential ISPs assign dynamic public IPs that can change at any time. This infrastructure has three critical dependencies on the home public IP:

1. **AWS Security Group** — restricts SSH, IPsec, and NPM admin to the home IP
2. **Fail2ban ignoreip** — whitelists the home IP to prevent admin self-lockout
3. **IPsec tunnel** — EC2's strongSwan uses `right=%any` for the initiator, but the Security Group must allow UDP 500/4500 from the current home IP

When the IP changes without updating these three places simultaneously, the result is a complete lockout: SSH access drops, the IPsec tunnel collapses, and Guacamole becomes unreachable.

---

## Solution Architecture

The solution uses a two-layer approach:

**Layer 1 — DuckDNS (Home → Internet)**
A free dynamic DNS service maps `aymane-lab.duckdns.org` to the current home public IP. A cron job on centos-vm2 updates this record every 5 minutes using a simple `curl` command.

**Layer 2 — Self-Healing Script (EC2)**
A script on EC2 runs every 5 minutes, resolves `aymane-lab.duckdns.org`, compares the result to the current Security Group rule, and automatically updates AWS + Fail2ban if the IP has changed.

```
Home IP changes
    ↓ (within 5 min)
centos-vm2 cron updates DuckDNS
    ↓ (within 5 min)
EC2 script detects mismatch
    ↓ (immediately)
Security Group + Fail2ban updated automatically
```

Maximum time from IP change to full restoration: **~10 minutes** (two 5-minute cron cycles).

---

## DuckDNS Setup

### Account Setup
1. Go to [duckdns.org](https://www.duckdns.org)
2. Log in with Google
3. Create subdomain: `aymane-lab` → `aymane-lab.duckdns.org`
4. Note your token (treat it like a password)

### Cron on centos-vm2

The DuckDNS update runs from centos-vm2 (VLAN 20 — Services), which has reliable internet access via pfSense NAT.

```bash
# Add to centos-vm2 root crontab (sudo crontab -e)
*/5 * * * * curl -s "https://www.duckdns.org/update?domains=aymane-lab&token=YOUR_TOKEN&ip=" > /dev/null
```

The `ip=` parameter left blank tells DuckDNS to auto-detect the source IP of the request. This is more reliable than trying to fetch the IP separately.

**Why centos-vm2, not pfSense?**
pfSense's built-in Dynamic DNS client proved unreliable — it silently failed to update DuckDNS during an IP change event. A simple `curl` cron on a Linux VM is more predictable and easier to debug.

---

## EC2 Self-Healing Script

See `update-sg-ip.sh` in this directory for the full script with inline comments.

### Installation on EC2

```bash
# Copy script to EC2
sudo nano /usr/local/bin/update-sg-ip.sh
# Paste content, then:
sudo chmod +x /usr/local/bin/update-sg-ip.sh

# Add to root crontab
sudo crontab -e
# Add line:
*/5 * * * * /usr/local/bin/update-sg-ip.sh > /dev/null 2>&1
```

### Required IAM Permissions

The script uses the default AWS CLI profile (`lab-sg-updater` IAM user). The policy grants only the minimum required permissions:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["ec2:DescribeSecurityGroups", "ec2:DescribeSecurityGroupRules"],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": ["ec2:AuthorizeSecurityGroupIngress", "ec2:RevokeSecurityGroupIngress"],
      "Resource": "arn:aws:ec2:eu-north-1:197654287376:security-group/sg-04bfe0b62b29ec7fa"
    }
  ]
}
```

### Monitoring

```bash
# View recent log entries
tail -20 /var/log/update-sg-ip.log

# Manual trigger (for testing)
sudo /usr/local/bin/update-sg-ip.sh

# Verify current DuckDNS resolution
dig +short aymane-lab.duckdns.org
```

---

## Emergency Recovery

If locked out before automation is working:

1. Go to `https://whatismyip.com` to find current home IP
2. Open **AWS Console → CloudShell** (no SSH needed)
3. Run:
```bash
aws ec2 authorize-security-group-ingress \
  --group-id sg-04bfe0b62b29ec7fa \
  --protocol tcp --port 22 --cidr YOUR_IP/32

aws ec2 authorize-security-group-ingress \
  --group-id sg-04bfe0b62b29ec7fa \
  --protocol udp --port 500 --cidr YOUR_IP/32

aws ec2 authorize-security-group-ingress \
  --group-id sg-04bfe0b62b29ec7fa \
  --protocol udp --port 4500 --cidr YOUR_IP/32
```
4. Force DuckDNS update: open `https://www.duckdns.org/update?domains=aymane-lab&token=TOKEN&ip=YOUR_IP` in browser
