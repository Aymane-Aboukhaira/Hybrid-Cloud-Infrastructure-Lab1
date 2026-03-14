# Hybrid Cloud Infrastructure Lab

> Built on a recycled Dell laptop (8 GB RAM) and AWS Free Tier credits.
> Five VMs. Four isolated VLANs. One IPsec site-to-site VPN tunnel. Six production incidents — all documented with root cause analysis.

This lab simulates a real enterprise hybrid cloud environment: on-premise Proxmox hypervisor
connected to AWS via IPsec IKEv2, with zero-trust VLAN segmentation, Active Directory
authentication, centralized monitoring, and a three-tier disaster recovery strategy.
Every component has been configured, broken, diagnosed, and repaired.

---

## Architecture

```
[Admin Workstation]
        |
        | HTTPS / SSH
        |
[Proxmox VE 8 — Dell Latitude E5470 — 192.168.11.50]
        |
        |── pfSense CE (Firewall + IPsec VPN Gateway)
        |       WAN: 192.168.11.x (DHCP) | LAN: VLAN trunk (10/20/30/40)
        |       |
        |       |════[ IPsec Site-to-Site — IKEv2 / AES-256 / SHA-256 / MODP2048 ]════
        |                                           |
        |                              AWS eu-north-1 (Stockholm)
        |                              EC2 lab-secure-edge — 51.20.237.223
        |                                ├── Nginx Proxy Manager + Let's Encrypt SSL
        |                                ├── Apache Guacamole (clientless RDP/SSH/SFTP)
        |                                ├── Fail2ban (DOCKER-USER chain)
        |                                └── S3 backups (write-only IAM)
        |
        |── VLAN 10 — Management (192.168.10.0/24)
        |       DC01 — Windows Server 2022 (AD DS · DNS · DHCP · LDAP)
        |
        |── VLAN 20 — Services (192.168.20.0/24)
        |       centos-vm2 — Prometheus · Grafana · Backup Master
        |
        |── VLAN 30 — DMZ (192.168.30.0/24)  [ISOLATED — no LAN access]
        |       centos-vm1 — node-exporter · future web app
        |
        └── VLAN 40 — Storage (192.168.40.0/24)
                omv-nas — OpenMediaVault (SMB + NFS)
```

---

## Incidents & Post-Mortems

This lab encountered real failures during build and operation. Each is documented with
symptoms, root cause, resolution, and the architectural change that followed.
This section exists because debugging complex infrastructure is the actual job.

| # | Incident | Root cause | What changed |
|---|---|---|---|
| 1 | [Fail2ban banned admin IP — killed SSH, VPN, and Guacamole simultaneously](incidents/incident-01-fail2ban-lockout.md) | Home IP shared by admin workstation and pfSense — banned my own IPsec endpoint during testing | `ignoreip` whitelist added; auto-updated by `update-sg-ip.sh` on every IP rotation |
| 2 | [IPsec tunnel silently dead — no errors, no connectivity](incidents/incident-02-ipsec-blackhole.md) | AWS Security Group blocked UDP 500/4500 after ISP changed home IP — strongSwan never received IKE packets | Recovered via AWS CloudShell; built self-healing Security Group automation |
| 3 | [pfSense built-in DDNS client failed silently for days](incidents/incident-03-ddns-silent-fail.md) | pfSense DDNS GUI tool stopped updating DuckDNS with no alert, no log, no visible error | Replaced with a single `cron` + `curl` on centos-vm2 — transparent and observable |
| 4 | [All VMs refused to start after VLAN configuration — QEMU exit code 1](incidents/incident-04-vlan-proxmox-crash.md) | Proxmox 9.1.1 strict validation requires a physical or dummy port on VLAN-aware bridges | Kernel dummy interface workaround; documented in `/etc/network/interfaces` with full comments |

---

## Key Design Decisions

**Zero-trust VLAN segmentation**
Four isolated VLANs with deny-by-default firewall rules enforced at pfSense. The DMZ
(centos-vm1) has zero access to Management, Services, or Storage — lateral movement after
a web app compromise is blocked before it reaches DC01 or the NAS. Every firewall rule is
documented with its threat model justification in [`infrastructure/pfsense/`](infrastructure/pfsense/).

**Self-healing EC2 firewall**
The home ISP assigns dynamic IPs. When it rotates, the AWS Security Group becomes stale
and the IPsec tunnel silently dies — learned this the hard way in Incident 2. `update-sg-ip.sh`
runs every 5 minutes on EC2: queries DuckDNS for the current home IP, compares it against
the live Security Group, updates all four restricted ports on mismatch, updates Fail2ban's
`ignoreip`, and restarts the service. Full recovery within ~10 minutes of any IP rotation.

**Write-only IAM for S3 backups**
The backup IAM user has `s3:PutObject` and `s3:ListBucket` only — no `GetObject`, no
`DeleteObject`. If credentials are ever exposed on a compromised VM, an attacker can
overwrite recent backups but cannot delete versioned history. S3 versioning is enabled;
a 7-day lifecycle policy keeps costs under $0.01/month.

**Why IPsec IKEv2 over WireGuard**
IPsec IKEv2 is the enterprise standard for site-to-site VPN — natively supported in pfSense,
all Cisco/Fortinet/Palo Alto hardware, and AWS VPN Gateway. WireGuard is excellent for
individual client VPNs. This choice reflects what actually appears in enterprise environments
and job descriptions.

**Why Proxmox over VMware ESXi**
Proxmox VE uses KVM/QEMU — the same hypervisor that powers AWS EC2. Open source,
no licensing cost, mature REST API, and growing adoption in SMEs and MSPs. Hypervisor
management skills transfer directly to cloud environments.

**Centralized backup master**
centos-vm2 SSHes into pfSense and centos-vm1 to pull configs, compresses everything
locally, then pushes to S3 in a single job. One IAM credential on one machine. One cron job
to monitor. One log file to check. Documented in [`backups/`](backups/).

---

## Three-Tier Disaster Recovery

| Tier | Media | Location | Scope | Frequency | RTO |
|---|---|---|---|---|---|
| 1 | USB vault (air-gapped EXT4) | On-site | 5 full VM snapshots (.vma.zst) | Manual | ~30 min per VM |
| 2 | AWS S3 (eu-north-1) | Off-site | EC2 configs — NPM, Guacamole, IPsec, Fail2ban | Daily 02:00 | ~20 min |
| 3 | AWS S3 (eu-north-1) | Off-site | On-prem configs — pfSense, CentOS, monitoring stack | Daily 03:00 | ~10 min |

Recovery procedures for each scenario are in [`backups/disaster-recovery.md`](backups/disaster-recovery.md).

---

## Authentication Flow

A browser anywhere in the world accessing DC01's desktop:

```
Browser (anywhere)
  │  HTTPS 443 — Let's Encrypt certificate
  ▼
EC2 51.20.237.223
  │  Nginx Proxy Manager — SSL termination, Host header validation
  ▼
Apache Guacamole (Docker — no port exposed directly, internal network only)
  │  LDAP 389 ──► IPsec tunnel ──► DC01 192.168.10.10  [AD credential check]
  │  TOTP ──────────────────────────────────────────────[6-digit second factor]
  ▼
RDP 3389 ──► IPsec tunnel ──► DC01
  ▼
Windows Server 2022 desktop rendered in the browser
```

DC01 is never exposed to the internet. LDAP traffic travels entirely inside the AES-256
IPsec tunnel. TOTP is enforced as a second factor after AD credentials.

---

## Infrastructure Summary

| Component | Role | Location | IP | RAM |
|---|---|---|---|---|
| Proxmox VE 8 | KVM hypervisor | Dell Latitude E5470 | 192.168.11.50 | host |
| pfSense CE | Firewall, NAT, IPsec, VLAN routing | VM — Proxmox | WAN: DHCP | 512 MB |
| DC01 — WinSrv 2022 | AD DS, DNS, DHCP, LDAP | VLAN 10 — 192.168.10.10 | static | 2 GB |
| centos-vm2 | Prometheus, Grafana, backup master | VLAN 20 — 192.168.20.30 | static | 1.5 GB |
| centos-vm1 | node-exporter, DMZ workload | VLAN 30 — 192.168.30.20 | static | 1 GB |
| omv-nas | OpenMediaVault, SMB + NFS | VLAN 40 — 192.168.40.40 | static | 1 GB |
| EC2 lab-secure-edge | Guacamole, NPM, Fail2ban | AWS eu-north-1 | 51.20.237.223 | 1 GB + 2 GB swap |
| IPsec tunnel | pfSense ↔ EC2 encrypted overlay | — | — | — |

Total on-premise RAM allocated: 6 GB across 5 VMs on an 8 GB machine.
Every allocation decision is documented in [`infrastructure/proxmox/`](infrastructure/proxmox/).

AWS cost: under $10/month on a $100 credit. S3 lifecycle keeps backup storage below $0.01/month.

---

## Skills Demonstrated

| Domain | Technologies |
|---|---|
| Virtualization | Proxmox VE 8, QEMU/KVM, VM lifecycle, VLAN-aware bridges, dummy interface workaround |
| Networking | pfSense, IPsec IKEv2, 802.1Q VLANs, NAT, inter-VLAN routing, zero-trust firewall rules |
| Linux | CentOS Stream 9, Ubuntu 24.04, SELinux, firewalld, systemd, NFS mounts, bash scripting |
| Windows | Windows Server 2022, AD DS, DNS, DHCP, GPO, PowerShell, windows-exporter |
| Cloud — AWS | EC2, VPC, Security Groups, IAM least privilege, S3 versioning + lifecycle, Elastic IP, CloudShell |
| Containers | Docker, Podman, Docker Compose, podman-compose, DOCKER-USER iptables chain |
| Monitoring | Prometheus, Grafana, node-exporter (Linux), windows-exporter (Windows), PromQL |
| Security | Fail2ban, TOTP MFA, AD LDAP, IPsec PSK, DMZ isolation, write-only IAM, defense in depth |
| Backup & DR | 3-2-1 strategy, Proxmox snapshots (.vma.zst), S3 versioning, FinOps lifecycle policies |
| Automation | Bash scripting, cron, AWS CLI, DuckDNS DDNS, self-healing firewall script |
| Remote Access | Apache Guacamole (clientless RDP/SSH/SFTP), Nginx Proxy Manager, Let's Encrypt SSL |
| Storage | OpenMediaVault, SMB shares, NFS persistent mounts (`_netdev`), EXT4 |


---

## Author

**Aymane Aboukhaira**
Networks & Systems — ISMONTIC, Tangier, Morocco | Graduating 2026
CCNA in progress (expected May 2026)
