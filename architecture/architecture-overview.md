# Architecture Overview

## Design Philosophy

This infrastructure follows three core principles:

**Defense in Depth** — No single security control is relied upon exclusively. Every access path has multiple independent security layers. If one fails, the others contain the blast radius.

**Least Privilege** — Every component has only the permissions it needs. IAM policies are scoped to specific resources and actions. Firewall rules allow only necessary traffic. VLAN isolation prevents lateral movement.

**Infrastructure as Documentation** — Every configuration decision is documented with its rationale. The goal is reproducibility: the entire lab should be rebuildable from this repository.

---

## Component Overview

### Hypervisor Layer — Proxmox VE 8

**Machine**: Dell Latitude E5470 | Intel i5 6th gen | 8GB RAM | 256GB SSD

Proxmox provides the virtualization foundation for all on-premise components. The 8GB RAM constraint required careful VM resource planning — no more than 3 VMs run simultaneously under full load.

**Bridge layout:**
| Bridge | Purpose | Attachment |
|---|---|---|
| vmbr0 | WAN uplink to home network | Physical NIC (nic0) |
| vmbr1 | Internal lab LAN (VLAN trunk) | dummy0 (kernel dummy interface) |

**Critical hardware fix**: The Intel I219-LM NIC on this hardware fails auto-negotiation under Linux. A permanent fix forces 100Mbps full-duplex:
```
iface nic0 inet manual
    pre-up ethtool -s nic0 speed 100 duplex full autoneg off
```

**VLAN implementation note**: Proxmox 9.1.1 requires a physical or dummy NIC attached to a VLAN-aware bridge. Since vmbr1 is a purely virtual switch, a kernel dummy interface (`dummy0`) was injected via `/etc/network/interfaces` hooks. This is a documented upstream limitation, not a bug.

---

### Network Layer — pfSense

pfSense is the central nervous system of the lab network. It provides:
- **NAT and routing** between the home network (WAN) and lab VLANs (LAN)
- **VLAN trunk** on vtnet0 (LAN), carrying 4 isolated network segments
- **IPsec site-to-site VPN** to AWS EC2 (IKEv2/AES-256)
- **DHCP** for all four VLANs
- **Inter-VLAN firewall rules** enforcing zero-trust segmentation
- **Keep-alive pings** to maintain the IPsec tunnel through residential NAT

---

### VLAN Segments

| VLAN | Name | Subnet | Gateway | Purpose |
|---|---|---|---|---|
| 10 | MGMT | 192.168.10.0/24 | 192.168.10.1 | Domain controller, management traffic |
| 20 | SERVICES | 192.168.20.0/24 | 192.168.20.1 | Monitoring, backup master |
| 30 | DMZ | 192.168.30.0/24 | 192.168.30.1 | Web application (isolated) |
| 40 | STORAGE | 192.168.40.0/24 | 192.168.40.1 | NAS (restricted access) |

**Inter-VLAN access matrix:**

| Source | MGMT | SERVICES | DMZ | STORAGE | Internet |
|---|---|---|---|---|---|
| MGMT | ✅ | ✅ | ✅ | ✅ | ✅ |
| SERVICES | ✅ | ✅ | ✅ | ✅ | ✅ |
| DMZ | ❌ | ❌ | ✅ | ❌ | ✅ |
| STORAGE | ❌ | ❌ | ❌ | ✅ | ❌ |

---

### On-Premise VMs

| VM | VLAN | IP | RAM | Role |
|---|---|---|---|---|
| pfSense | — | WAN: 192.168.11.x, LAN: gateway per VLAN | — | Firewall / VPN |
| DC01 | VLAN 10 | 192.168.10.10 | 2GB | Windows Server 2022 — AD DS, DNS, DHCP |
| centos-vm2 | VLAN 20 | 192.168.20.30 | 1GB | Prometheus, Grafana, backup master |
| centos-vm1 | VLAN 30 | 192.168.30.20 | 1GB | node-exporter, future web app (DMZ) |
| omv-nas | VLAN 40 | 192.168.40.40 | 1GB | OpenMediaVault — SMB + NFS |

**Boot order** (configured in Proxmox for power recovery):
1. pfSense (delay: 30s) — routing and DHCP must be available first
2. DC01 (delay: 60s) — AD/DNS must be ready before domain-joined services start
3. centos-vm1, centos-vm2, omv-nas (delay: 30s each)

---

### Cloud Layer — AWS EC2

**Instance**: lab-secure-edge | Ubuntu 24.04 | t3.micro | Elastic IP: 51.20.237.223
**Region**: eu-north-1 (Stockholm)

The EC2 instance acts as the secure cloud edge. All public-facing services terminate here. The lab network is never directly exposed to the internet.

**Services running on EC2 (Docker):**

| Service | Port | Exposure |
|---|---|---|
| Nginx Proxy Manager | 80, 443 | Public (reverse proxy + SSL) |
| NPM Admin | 81 | Home IP only |
| Apache Guacamole | Internal | Via NPM only (no direct binding) |
| PostgreSQL 15 | Internal | Docker bridge only |
| guacd | Internal | Docker bridge only |

**Memory management**: t3.micro has 1GB RAM. A 2GB swapfile (`/swapfile`) is configured persistently via `/etc/fstab` to prevent OOM kills under the combined Docker container load.

---

### IPsec VPN Tunnel

The site-to-site VPN connects the on-premise lab (192.168.1.0/24 → migrating to VLAN subnets) to the AWS VPC (10.0.0.0/16).

**Why asymmetric configuration is required:**
- pfSense sits behind a residential NAT with a dynamic public IP
- pfSense must be the **initiator** (`auto=start`) so it can punch through NAT
- EC2 must be the **responder** (`auto=add`, `right=%any`) to accept connections from any IP
- EC2 uses `dpdaction=clear` — if the tunnel drops, it clears state and waits for pfSense to re-initiate
- pfSense uses `dpdaction=restart` — if the tunnel drops, it immediately tries to reconnect

**Encryption parameters:**
- IKEv2, AES-256, SHA-256, DH Group 14 (MODP2048)
- ESP: AES-256, SHA-256, PFS disabled (to match EC2 `esp=aes256-sha256!`)
- Phase 1 lifetime: 28800s | Phase 2 lifetime: 3600s

---

### Security Stack

**Layer 1 — Network perimeter (AWS Security Group)**
- Port 22 (SSH): home IP only
- Port 81 (NPM admin): home IP only
- Port 80/443 (HTTPS): open
- UDP 500/4500 (IPsec): home IP only
- Auto-updated by `update-sg-ip.sh` when dynamic home IP changes

**Layer 2 — Application perimeter (Fail2ban)**
- Reads real client IPs from NPM access logs
- Bans IPs after 5 failures in 10 minutes (1-hour ban)
- Rules injected into Docker's DOCKER-USER iptables chain
- Home IP whitelisted to prevent admin lockout

**Layer 3 — Identity (AD LDAP + TOTP)**
- Guacamole authenticates against Active Directory (lab.local) via LDAP
- TOTP MFA enforced as second factor — 6-digit rotating code
- No unauthenticated access to any internal resource

---

### Monitoring Stack

**Deployed on centos-vm2 (192.168.20.30) via podman-compose:**

| Component | Port | Role |
|---|---|---|
| Prometheus | 9090 | Metrics collection and storage |
| Grafana | 3000 | Visualization and dashboards |
| node-exporter | 9100 | centos-vm2 host metrics |

**Prometheus targets:**
| Target | Exporter | Port | Status |
|---|---|---|---|
| centos-vm1 | node-exporter | 9100 | ✅ |
| centos-vm2 | node-exporter | 9100 | ✅ |
| DC01 | windows-exporter | 9182 | ✅ |
| prometheus | self | 9090 | ✅ |

---

### Disaster Recovery — Three Tiers

| Tier | Medium | Scope | RTO | Automation |
|---|---|---|---|---|
| 1 (Physical) | USB drive (ext4) | 5 full VM snapshots | ~30min | Manual (Proxmox GUI) |
| 2 (Cloud Edge) | AWS S3 | EC2 configs (NPM, Guacamole, IPsec, Fail2ban) | ~15min | Daily at 2AM |
| 3 (Cloud On-Prem) | AWS S3 | pfSense config.xml, CentOS configs, monitoring stack | ~20min | Daily at 3AM |

S3 bucket: `aymane-lab-backups` (eu-north-1, versioning enabled, 7-day expiry lifecycle)
IAM: write-only policy (`s3:PutObject` + `s3:ListBucket` only — no delete permission)
