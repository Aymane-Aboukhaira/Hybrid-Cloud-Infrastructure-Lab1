#!/bin/bash
# =============================================================================
# s3-backup.sh — EC2 Configuration Backup to S3
# =============================================================================
# Author:  Aymane Aboukhaira
# Project: Hybrid Cloud Infrastructure Lab
# Purpose: Backs up critical EC2 configuration files to S3 (Tier 2 DR).
#
# Backup scope:
#   - /opt           → NPM and Guacamole docker-compose files + data
#   - /etc/fail2ban  → Custom jails, filters, whitelist
#   - /etc/ipsec.*   → strongSwan VPN tunnel config and PSK
#
# Security design:
#   - Uses 's3-backup' AWS CLI named profile (lab-s3-backup-bot IAM user)
#   - IAM policy: PutObject + ListBucket ONLY — no delete permission
#   - Even if EC2 is fully compromised, attacker cannot delete backups
#
# S3 path: s3://aymane-lab-backups/ec2/<hostname>/<filename>
# Lifecycle: 7-day expiry (FinOps — protects $100 AWS credit budget)
#
# Cron: 0 2 * * * /usr/local/bin/s3-backup.sh
# =============================================================================

BUCKET="s3://aymane-lab-backups"
HOSTNAME=$(hostname -s)
DATE=$(date '+%Y-%m-%d_%H-%M')
BACKUP_DIR="/tmp/backups"
LOGFILE="/var/log/s3-backup.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a $LOGFILE
}

mkdir -p $BACKUP_DIR

log "Starting backup for $HOSTNAME..."

# Backup /opt — contains NPM and Guacamole docker-compose files and config data
# Using -C / opt (not /opt) avoids "Removing leading /" warning from tar
tar -czf $BACKUP_DIR/opt_$DATE.tar.gz -C / opt 2>/dev/null
log "Compressed /opt -> opt_$DATE.tar.gz"

# Backup /etc/fail2ban — custom jail.local, npm-general filter, whitelist
tar -czf $BACKUP_DIR/fail2ban_$DATE.tar.gz -C / etc/fail2ban 2>/dev/null
log "Compressed /etc/fail2ban -> fail2ban_$DATE.tar.gz"

# Backup IPsec config — ipsec.conf (tunnel parameters) + ipsec.secrets (PSK)
# Critical: without these, VPN tunnel cannot be reconstructed after an EC2 rebuild
tar -czf $BACKUP_DIR/ipsec_$DATE.tar.gz -C / etc/ipsec.conf etc/ipsec.secrets 2>/dev/null
log "Compressed IPsec config -> ipsec_$DATE.tar.gz"

# Upload all archives to S3
# $? -eq 0 check: only delete local archive if upload succeeded
# This prevents data loss from a failed upload followed by local deletion
for FILE in $BACKUP_DIR/*_$DATE.tar.gz; do
    aws s3 cp $FILE $BUCKET/ec2/$HOSTNAME/$(basename $FILE) --profile s3-backup
    if [ $? -eq 0 ]; then
        log "Uploaded $(basename $FILE) to S3"
        rm -f $FILE
    else
        log "ERROR: Failed to upload $(basename $FILE) — local copy retained"
    fi
done

log "Backup complete."
