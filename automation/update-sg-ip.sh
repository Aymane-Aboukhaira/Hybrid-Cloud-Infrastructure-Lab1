#!/bin/bash
# =============================================================================
# update-sg-ip.sh — Self-Healing AWS Security Group Updater
# =============================================================================
# Author:  Aymane Aboukhaira
# Project: Hybrid Cloud Infrastructure Lab
# Purpose: Automatically updates AWS Security Group inbound rules when the
#          home ISP's dynamic public IP changes. Also updates Fail2ban's
#          ignoreip whitelist to prevent admin self-lockout.
#
# How it works:
#   1. Resolves aymane-lab.duckdns.org to get the current home public IP
#      (DuckDNS is updated every 5 minutes by a cron on centos-vm2)
#   2. Queries the current AWS Security Group to get the IP currently allowed
#   3. If IPs differ, revokes the old rules and authorizes new ones for all
#      critical ports: SSH (22), NPM admin (81), IPsec IKE (UDP 500/4500)
#   4. Updates Fail2ban ignoreip to whitelist the new home IP
#   5. Logs every action to /var/log/update-sg-ip.log
#
# Cron: */5 * * * * /usr/local/bin/update-sg-ip.sh > /dev/null 2>&1
# =============================================================================

SG_ID="sg-04bfe0b62b29ec7fa"
DDNS_HOST="aymane-lab.duckdns.org"
F2B_CONFIG="/etc/fail2ban/jail.local"
LOGFILE="/var/log/update-sg-ip.log"
PORTS=("22/tcp" "81/tcp" "500/udp" "4500/udp")

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a $LOGFILE
}

# Step 1: Get current home IP from DuckDNS
# dig +short returns just the IP, tail -1 handles edge cases with multiple answers
HOME_IP=$(dig +short $DDNS_HOST | tail -1)

if [ -z "$HOME_IP" ]; then
    log "ERROR: Could not resolve $DDNS_HOST — skipping update"
    exit 1
fi

# Step 2: Get the IP currently authorized in the Security Group
# We use port 22 TCP as the reference rule — if it's set, all others should be too
CURRENT_SG_IP=$(aws ec2 describe-security-groups \
    --group-ids $SG_ID \
    --query 'SecurityGroups[0].IpPermissions[?ToPort==`22`].IpRanges[0].CidrIp' \
    --output text | cut -d'/' -f1)

# Step 3: Compare — exit early if no change needed
if [ "$HOME_IP" == "$CURRENT_SG_IP" ]; then
    log "IP unchanged ($HOME_IP) — no update needed"
    exit 0
fi

log "IP changed: $CURRENT_SG_IP -> $HOME_IP — updating..."

# Step 4: Update each port
for PORT_PROTO in "${PORTS[@]}"; do
    PORT=$(echo $PORT_PROTO | cut -d'/' -f1)
    PROTO=$(echo $PORT_PROTO | cut -d'/' -f2)

    # Revoke old IP (2>/dev/null suppresses errors if rule doesn't exist)
    aws ec2 revoke-security-group-ingress \
        --group-id $SG_ID \
        --protocol $PROTO \
        --port $PORT \
        --cidr ${CURRENT_SG_IP}/32 2>/dev/null

    # Authorize new IP
    aws ec2 authorize-security-group-ingress \
        --group-id $SG_ID \
        --protocol $PROTO \
        --port $PORT \
        --cidr ${HOME_IP}/32

    log "Updated port $PORT/$PROTO: $CURRENT_SG_IP -> $HOME_IP"
done

# Step 5: Update Fail2ban whitelist to prevent admin self-lockout
# The ignoreip directive tells Fail2ban never to ban these IPs
sed -i "s|ignoreip = .*|ignoreip = 127.0.0.1/8 $HOME_IP|" $F2B_CONFIG
systemctl restart fail2ban
log "Fail2ban ignoreip updated to $HOME_IP"
log "Done."
