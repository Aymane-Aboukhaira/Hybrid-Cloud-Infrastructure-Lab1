# Disaster Recovery Plan

## DR Strategy Overview

This infrastructure follows the **3-2-1 backup rule**:
- **3** copies of data
- **2** different storage media types
- **1** copy offsite

| Tier | Media | Location | Scope | RTO |
|---|---|---|---|---|
| Tier 1 | USB Drive (ext4) | On-site (physical) | Full VM snapshots | ~30 min |
| Tier 2 | AWS S3 | Cloud (eu-north-1) | EC2 configs | ~15 min |
| Tier 3 | AWS S3 | Cloud (eu-north-1) | On-prem configs | ~20 min |

---

## Tier 1 — Physical USB Vault

### What's Backed Up
- pfSense VM snapshot (.vma.zst)
- DC01 VM snapshot (.vma.zst)
- centos-vm1 VM snapshot (.vma.zst)
- centos-vm2 VM snapshot (.vma.zst)
- omv-nas VM snapshot (.vma.zst)

### Setup
```bash
# Format USB drive (wipes all existing data)
sudo mkfs.ext4 -F /dev/sda1

# Mount the drive
sudo mkdir -p /mnt/usb
sudo mount /dev/sda1 /mnt/usb

# Create required subdirectory (Proxmox requires /dump for backup content)
sudo mkdir -p /mnt/usb/dump
```

**Proxmox GUI Integration:**
1. Datacenter → Storage → Add → Directory
2. ID: `USB-Offline-Vault`
3. Directory: `/mnt/usb`
4. Content: Backup (only)
5. Save

### Backup Process
1. Proxmox → Backup → select VM → backup to USB-Offline-Vault
2. Format: .vma.zst (compressed)
3. Transfer method: `rsync -avh --progress --fsync /path/to/vma /mnt/usb/dump/`
   - `--fsync` flag critical for USB 2.0 — forces hardware writes to prevent RAM buffer overflow

### Recovery Process
1. Plug in USB drive, mount at `/mnt/usb`
2. Proxmox → Backup → select snapshot → Restore
3. Full VM restored in ~10-20 minutes

---

## Tier 2 — EC2 S3 Backup

### What's Backed Up
| Archive | Contents | Why |
|---|---|---|
| `opt_DATE.tar.gz` | /opt (NPM + Guacamole docker-compose + data) | Rebuild entire cloud edge stack |
| `fail2ban_DATE.tar.gz` | /etc/fail2ban (jails + filters) | Restore security config |
| `ipsec_DATE.tar.gz` | /etc/ipsec.conf + ipsec.secrets | Restore VPN tunnel config + PSK |

### Schedule
Daily at 2:00 AM — `0 2 * * * /usr/local/bin/s3-backup.sh`

### S3 Configuration
- Bucket: `aymane-lab-backups`
- Path: `s3://aymane-lab-backups/ec2/ip-10-0-1-99/`
- Versioning: Enabled
- Lifecycle: Expire after 7 days (cost control)
- IAM: Write-only (`PutObject` + `ListBucket` — no delete)

### Recovery Process
```bash
# Download latest backup from S3
aws s3 ls s3://aymane-lab-backups/ec2/ip-10-0-1-99/ --profile s3-backup
aws s3 cp s3://aymane-lab-backups/ec2/ip-10-0-1-99/opt_DATE.tar.gz . --profile s3-backup

# Extract
tar -xzf opt_DATE.tar.gz -C /

# Restart services
cd /opt && docker-compose up -d
```

---

## Tier 3 — On-Premise S3 Backup

### What's Backed Up
| Archive | Contents | Why |
|---|---|---|
| `pfsense-config_DATE.xml` | pfSense config.xml | Rebuild entire router config |
| `centos-vm1_configs_DATE.tar.gz` | /opt/node-exporter | Restore monitoring agent |
| `centos-vm2_monitoring_DATE.tar.gz` | /opt/monitoring | Restore Prometheus + Grafana |

### Schedule
Daily at 3:00 AM — `0 3 * * * /usr/local/bin/onprem-s3-backup.sh`

### pfSense Recovery
1. Fresh pfSense install
2. Diagnostics → Backup & Restore → Restore Backup
3. Upload `pfsense-config_DATE.xml`
4. pfSense reboots with full config restored

### Monitoring Stack Recovery
```bash
# On centos-vm2
aws s3 cp s3://aymane-lab-backups/on-prem/centos-vm2_monitoring_DATE.tar.gz . --profile s3-backup
tar -xzf centos-vm2_monitoring_DATE.tar.gz -C /opt/
cd /opt/monitoring && podman-compose up -d
```

---

## IAM Security Design

The backup IAM user (`lab-s3-backup-bot`) has a write-only policy:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:PutObject", "s3:ListBucket"],
      "Resource": [
        "arn:aws:s3:::aymane-lab-backups",
        "arn:aws:s3:::aymane-lab-backups/*"
      ]
    }
  ]
}
```

**Why no delete permission?** If a ransomware attack or full server compromise occurs, the attacker can find the AWS credentials in the cron environment. With only `PutObject`, they can overwrite backups with garbage but cannot delete them. S3 versioning means the previous clean backup is still recoverable.

---

## DR Scenarios

| Scenario | Recovery Path | Estimated Time |
|---|---|---|
| EC2 instance terminated | Rebuild EC2, restore from S3 Tier 2 | 20-30 min |
| Proxmox hardware failure | New hardware + Proxmox install, restore VMs from USB | 1-2 hours |
| pfSense config corruption | Upload config.xml backup via web UI | 5 min |
| centos-vm2 data loss | Restore from S3 Tier 3, restart containers | 15 min |
| Complete lab destruction | Provision new hardware, restore all from USB + S3 | 2-4 hours |
| IPsec tunnel broken | Restore ipsec.conf + ipsec.secrets from S3 Tier 2 | 10 min |
