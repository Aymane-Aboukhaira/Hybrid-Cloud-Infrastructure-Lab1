#!/bin/bash
# =============================================================================
# onprem-s3-backup.sh — On-Premise Multi-Node Backup to S3
# =============================================================================
# Author:  Aymane Aboukhaira
# Project: Hybrid Cloud Infrastructure Lab
# Purpose: Centralized backup of all on-premise node configurations to S3.
#          Runs on centos-vm2 (Backup Master) and reaches out to other nodes.
#
# Architecture — Centralized Backup Pattern:
#   centos-vm2 is the "Backup Master". Instead of installing AWS credentials
#   on every VM, this single script pulls configs from other nodes via SSH/SCP
#   and uploads everything in one pass. One IAM profile, one cron, one log.
#
# Backup scope:
#   - pfSense  (192.168.10.1):  /cf/conf/config.xml via SCP (18KB — full router config)
#   - centos-vm1 (192.168.30.20): /opt/node-exporter via SSH tar stream
#   - centos-vm2 (local):        /opt/monitoring (Prometheus + Grafana configs)
#
# Prerequisites:
#   - Passwordless SSH from centos-vm2 root to centos-vm1 root (ed25519 key)
#   - Passwordless SSH from centos-vm2 root to pfSense admin
#   - AWS CLI configured: sudo aws configure --profile s3-backup
#   - System clock synchronized (chrony) — AWS rejects requests >15min skewed
#
# S3 path: s3://aymane-lab-backups/on-prem/<filename>
# Cron: 0 3 * * * /usr/local/bin/onprem-s3-backup.sh
# =============================================================================

BUCKET="s3://aymane-lab-backups/on-prem"
DATE=$(date '+%Y-%m-%d_%H-%M')
BACKUP_DIR="/tmp/onprem-backups"
LOGFILE="/var/log/onprem-s3-backup.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a $LOGFILE
}

mkdir -p "$BACKUP_DIR"
log "Starting On-Premise backup sequence..."

# --- TASK 1: pfSense config.xml ---
# pfSense stores its entire configuration in a single XML file (~18KB).
# This includes all firewall rules, VPN config, DHCP leases, NAT rules, etc.
# Restoring this file via Diagnostics > Backup & Restore rebuilds the entire router.
log "Pulling pfSense config.xml from 192.168.10.1..."
scp admin@192.168.10.1:/cf/conf/config.xml "$BACKUP_DIR/pfsense-config_$DATE.xml" 2>/dev/null
if [ $? -eq 0 ]; then
    log "pfSense config.xml pulled successfully."
else
    log "WARNING: Could not pull pfSense config — skipping."
fi

# --- TASK 2: centos-vm1 configs (Remote SSH tar stream) ---
# Instead of copying files then tarring, we stream the tar directly over SSH.
# This avoids leaving uncompressed data on the remote host.
log "Pulling configs from centos-vm1 (192.168.30.20)..."
ssh root@192.168.30.20 "tar -cz -C /opt node-exporter" > "$BACKUP_DIR/centos-vm1_configs_$DATE.tar.gz"
if [ $? -eq 0 ]; then
    log "centos-vm1 configs pulled."
else
    log "WARNING: Could not pull centos-vm1 configs — skipping."
fi

# --- TASK 3: centos-vm2 monitoring stack (Local) ---
# Backs up Prometheus config (prometheus.yml, alert rules) and Grafana
# dashboard JSON exports. Combined with the podman-compose file in /opt/monitoring,
# this is enough to fully reconstruct the monitoring stack.
log "Compressing local Monitoring stack (Prometheus/Grafana)..."
tar -czf "$BACKUP_DIR/centos-vm2_monitoring_$DATE.tar.gz" -C /opt monitoring 2>/dev/null
log "centos-vm2 monitoring stack compressed."

# --- TASK 4: Upload all archives to S3 ---
for FILE in "$BACKUP_DIR"/*"$DATE"*; do
    if [ -f "$FILE" ]; then
        log "Uploading $(basename "$FILE") to S3..."
        aws s3 cp "$FILE" "$BUCKET/$(basename "$FILE")" --profile s3-backup
        if [ $? -eq 0 ]; then
            log "Uploaded $(basename "$FILE") successfully."
            rm -f "$FILE"
        else
            log "ERROR: Failed to upload $(basename "$FILE") — local copy retained."
        fi
    fi
done

log "On-Premise backup sequence complete."
