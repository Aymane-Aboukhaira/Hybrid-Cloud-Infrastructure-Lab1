# Technical Implementation Report
**Project:** Hybrid Cloud Infrastructure Lab
**Author:** Aymane Aboukhaira
**Period:** January – March 2026

---

## 1. Implementation Summary

This report documents the step-by-step technical implementation of a hybrid cloud infrastructure lab over three months, from initial Proxmox installation through enterprise security hardening. All configurations are reproducible from this repository.

---

## 2. Month 1 — Core Infrastructure

### 2.1 Proxmox VE Installation

Proxmox VE 8 was installed bare-metal on a Dell Latitude E5470. The first obstacle was network instability: the Intel I219-LM NIC failed auto-negotiation under the Proxmox/Linux kernel.

**Root cause**: Linux's auto-negotiation implementation is incompatible with certain Dell hardware configurations.

**Fix applied** to `/etc/network/interfaces`:
```
iface nic0 inet manual
    pre-up ethtool -s nic0 speed 100 duplex full autoneg off
```

**Bridge layout configured:**
- `vmbr0`: Physical NIC — WAN uplink to home network
- `vmbr1`: Virtual bridge — isolated lab LAN

### 2.2 pfSense Deployment

pfSense CE deployed as a VM with dual NIC:
- `vtnet0` → vmbr0 (WAN: 192.168.11.x via home DHCP)
- `vtnet1` → vmbr1 (LAN: 192.168.1.1/24 initially, later VLAN trunk)

NAT configured for all LAN → WAN traffic. Firewall rules: block LAN-initiated WAN access except DNS and HTTP/HTTPS.

### 2.3 Windows Server 2022 — Active Directory

DC01 deployed with 2GB RAM (minimum viable for AD DS). Configuration sequence:
1. Static IP: 192.168.1.10 (later migrated to 192.168.10.10)
2. Hostname: DC01
3. AD DS role installed and forest promoted (lab.local)
4. DNS: authoritative for lab.local, forwarder to 8.8.8.8
5. DHCP scope: 192.168.1.50–192.168.1.99
6. Windows Exporter installed for Prometheus monitoring

### 2.4 CentOS VMs

centos-vm1 and centos-vm2 cloned from a base CentOS 9 template:
- SELinux: enforcing (default, not changed)
- QEMU guest agent: installed and enabled
- Static IPs configured via NetworkManager
- firewalld: opened only required service ports
- podman-restart service enabled for container auto-start

### 2.5 Monitoring Stack

Deployed on centos-vm2 via podman-compose:

```bash
cd /opt/monitoring
cat > docker-compose.yml << 'EOF'
# [see services/monitoring/docker-compose.yml]
EOF
podman-compose up -d
```

All three Prometheus targets confirmed UP within 15 minutes:
- centos-vm1 node-exporter (9100) ✅
- centos-vm2 node-exporter (9100) ✅
- DC01 windows-exporter (9182) ✅

Grafana dashboards imported by ID: Node Exporter Full (1860) and Windows Exporter 2024 (20763).

---

## 3. Month 2 — Storage Layer

### 3.1 OpenMediaVault NAS

OMV deployed from official ISO with 1GB RAM and 30GB virtual disk. Configuration:
- ext4 filesystem formatted on data disk
- SMB share: `lab-share` (user: aymane)
- NFS export: accessible to 192.168.1.0/24

**NFS persistent mount on centos-vm1:**
```bash
echo "192.168.1.40:/srv/.../lab-share  /mnt/nas  nfs  defaults,_netdev  0  0" >> /etc/fstab
mount -a
```

The `_netdev` mount option prevents boot failures if NAS is unavailable at startup by instructing systemd to mount after network is ready.

---

## 4. Month 3 — Cloud Integration

### 4.1 AWS Infrastructure Provisioning

VPC and subnet provisioned in eu-north-1 (Stockholm) for lowest Morocco→Europe latency:
- VPC: 10.0.0.0/16
- Public subnet: 10.0.1.0/24
- Internet Gateway attached
- Route table: 0.0.0.0/0 → IGW

EC2 instance (`lab-secure-edge`): Ubuntu 24.04, t3.micro, 20GB gp3, Elastic IP 51.20.237.223.

**Memory optimization** (t3.micro = 1GB RAM):
```bash
fallocate -l 2G /swapfile && chmod 600 /swapfile
mkswap /swapfile && swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab
```

### 4.2 IPsec Site-to-Site VPN

**EC2 strongSwan responder configuration:**
Key parameters:
- `auto=add` (wait for pfSense to initiate)
- `right=%any` (accept dynamic home IP)
- `dpdaction=clear` (clear state on dead peer, wait for reconnect)
- `forceencaps=yes` (force NAT-T even if not detected)

**pfSense initiator configuration:**
- `auto=start` (immediately establish tunnel on startup)
- `dpdaction=restart` (reconnect automatically if tunnel drops)
- Keep-alive ping to 10.0.1.99 (maintains NAT state table)

**Tunnel verification:**
```bash
# EC2
sudo ipsec statusall | grep ESTABLISHED
ping -c 3 192.168.1.10    # DC01
ping -c 3 192.168.1.20    # centos-vm1
# All responding at ~109ms RTT ✅
```

### 4.3 Guacamole Stack Deployment

**Critical lessons from deployment:**

1. **502 Bad Gateway**: NPM and Guacamole must be on the same Docker network. Solution: create external bridge `lab-edge-net` and add both containers to it. Remove direct port bindings from Guacamole (security: never expose Guacamole directly).

2. **PostgreSQL env var bug**: Newer Guacamole requires `POSTGRESQL_` prefix, not `POSTGRES_`. Using wrong prefix causes silent auth failure.

3. **LDAP over IPsec**: Setting `LDAP_HOSTNAME: 192.168.1.10` in Guacamole docker-compose routes authentication traffic through the IPsec tunnel. DC01 never needs a public IP.

**Connections configured:**
| Name | Protocol | Host | Features |
|---|---|---|---|
| DC01 - Windows Server | RDP | 192.168.10.10:3389 | NLA, 16-bit color, display-update resize |
| centos-vm1 - SSH | SSH | 192.168.30.20:22 | SFTP enabled |
| centos-vm2 - SSH | SSH | 192.168.20.30:22 | SFTP enabled |
| OMV NAS - SSH | SSH | 192.168.40.40:22 | SFTP to lab-share |

### 4.4 Fail2ban — DOCKER-USER Chain Solution

Standard Fail2ban tutorials fail in containerized environments because Docker bypasses the INPUT chain. The solution:

```ini
# /etc/fail2ban/jail.local [npm-docker]
action = iptables-multiport[name="npm-docker", port="http,https", protocol="tcp", chain="DOCKER-USER"]
logpath = /opt/npm/data/logs/proxy-host-*_access.log
```

The NPM log path was key: it contains real client IPs, not Docker internal IPs. Verified with live-fire test: exactly 5 failures → IP appears in `iptables -n -L DOCKER-USER`.

### 4.5 Dynamic IP Automation

**Architecture evolution:**

1. **v1 (pfSense DDNS)**: Unreliable — pfSense DDNS client silently failed on IP change. Replaced.
2. **v2 (centos-vm2 cron)**: More reliable but single point of failure during VLAN migration.
3. **v3 (current)**: Two-layer — centos-vm2 updates DuckDNS every 5 minutes; EC2 queries DuckDNS every 5 minutes and updates Security Group if IP changed.

Maximum recovery time after IP change: 10 minutes. Verified across multiple ISP IP rotations.

### 4.6 S3 Backup Pipeline

**IAM least privilege principle applied:**
- `lab-sg-updater`: read + modify specific SG only
- `lab-s3-backup-bot`: write to S3 only, no delete

**Write-only backup design** (Ransomware protection):
```json
{
  "Action": ["s3:PutObject", "s3:ListBucket"],
  "Resource": "arn:aws:s3:::aymane-lab-backups/*"
}
```

S3 versioning + 7-day lifecycle expiry = historical recovery without infinite cost accumulation.

---

## 5. Phase 1 — Network Segmentation (In Progress)

### 5.1 Proxmox VLAN Challenge

**Problem**: Assigning VLAN tag 30 to centos-vm1 on vmbr1 caused `QEMU exited with code 1, status 6400`.

**Root cause**: Proxmox 9.1.1 `pve-bridge` validation requires at least one physical NIC attached to a VLAN-aware bridge. vmbr1 is purely virtual.

**Solution**: Kernel dummy interface injected via `/etc/network/interfaces`:
```
auto dummy0
iface dummy0 inet manual
    pre-up ip link add dummy0 type dummy || true
    post-down ip link delete dummy0 type dummy || true
```
dummy0 bound to vmbr1 as bridge-ports, bridge-vlan-aware enabled, reloaded with `ifreload -a`.

### 5.2 pfSense VLAN Trunk

Created 4 VLAN sub-interfaces on vtnet0 (LAN):
- vtnet0.10 → MGMT (192.168.10.1/24)
- vtnet0.20 → SERVICES (192.168.20.1/24)
- vtnet0.30 → DMZ (192.168.30.1/24)
- vtnet0.40 → STORAGE (192.168.40.1/24)

DHCP configured per VLAN. DMZ uses 8.8.8.8 for DNS (no internal DNS access).

### 5.3 VM Migration

| VM | Old IP | New IP | VLAN |
|---|---|---|---|
| DC01 | 192.168.1.10 | 192.168.10.10 | 10 |
| centos-vm2 | 192.168.1.30 | 192.168.20.30 | 20 |
| centos-vm1 | 192.168.1.20 | 192.168.30.20 | 30 |
| omv-nas | 192.168.1.40 | 192.168.40.40 | 40 |

**Post-migration Prometheus fix**: `prometheus.yml` targets updated from old /24 IPs to new VLAN IPs. All 4 targets returned to UP status within 30 seconds of restart.

---

## 6. Incident Log

| # | Date | Incident | Resolution |
|---|---|---|---|
| 1 | Month 3 | Fail2ban banned admin IP, collapsed IPsec tunnel | Unban via fail2ban-client, add home IP to ignoreip |
| 2 | Month 3 | ISP IP change → silent SG lockout | Update SG manually, automate with DuckDNS script |
| 3 | Month 3 | pfSense DDNS client silent failure | Replace with cron curl on centos-vm2 |
| 4 | Phase 1 | Proxmox VLAN bridge crash (QEMU exit 1) | Kernel dummy interface workaround |
| 5 | Phase 1 | Docker networking desync after VM IP change | podman-compose down + up, update prometheus.yml |
| 6 | Phase 1 | centos-vm2 clock drift → AWS RequestTimeTooSkewed | date -s to correct time, re-enable chronyd |

---

## 7. Skills Demonstrated by Component

| Component | Skills |
|---|---|
| Proxmox VE + VLAN | Hypervisor management, 802.1Q trunking, bridge networking |
| pfSense IPsec | IKEv2, NAT traversal, asymmetric VPN design, firewall policy |
| AWS EC2/VPC/SG/IAM/S3 | Cloud infrastructure, IAM least privilege, FinOps |
| Guacamole + NPM | Container orchestration, reverse proxy, SSL, remote access |
| AD + LDAP + TOTP | Directory services, enterprise authentication, MFA |
| Fail2ban | Intrusion prevention, iptables, Docker networking internals |
| Prometheus + Grafana | Metrics collection, visualization, multi-OS monitoring |
| Bash automation | Infrastructure scripting, cron, AWS CLI, error handling |
| 3-tier DR | Backup strategy, S3, Proxmox snapshots, recovery procedures |
