# Hybrid Cloud Infrastructure Lab

> Built on a recycled Dell laptop (8 GB RAM) and AWS Free Tier credits.
> Five VMs. Four isolated VLANs. One IPsec site-to-site VPN tunnel. Six production incidents — all documented with root cause analysis.

This lab simulates a real enterprise hybrid cloud environment: on-premise Proxmox hypervisor connected to AWS via IPsec IKEv2, with zero-trust VLAN segmentation, Active Directory authentication, centralized monitoring, and a three-tier disaster recovery strategy. Every component has been configured, broken, diagnosed, and repaired.

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

> **Proof it runs:** `<!-- Add screenshot: architecture/diagrams/prometheus-targets.png -->`
> Replace this comment with a screenshot of Prometheus Targets showing all 4 nodes green.

---

## Incidents & Post-Mortems

This lab encountered real failures during build and operation. Each is documented
with symptoms, root cause, resolution, and the architectural change that followed.
This section exists because debugging complex infrastructure is the actual job.

| # | Incident | Root cause | What changed |
|---|---|---|---|
| 1 | [Fail2ban banned admin IP — killed SSH, VPN, and Guacamole simultaneously](incidents/incident-01-fail2ban-lockout.md) | Home IP shared by admin workstation and pfSense — banned my own IPsec endpoint during testing | `ignoreip` whitelist added; now auto-updated by `update-sg-ip.sh` on every IP rotation |
| 2 | [IPsec tunnel silently dead — no errors, no connectivity](incidents/incident-02-ipsec-blackhole.md) | AWS Security Group blocked UDP 500/4500 after ISP changed home IP — strongSwan never received IKE packets | Recovered via AWS CloudShell (only remaining access); built self-healing SG automation |
| 3 | [pfSense built-in DDNS client failed silently for days](incidents/incident-03-ddns-silent-fail.md) | pfSense DDNS GUI tool stopped updating DuckDNS with no alert, no log, no visible error | Replaced with a single `cron` + `curl` on centos-vm2 — transparent, testable, observable |
| 4 | [All VMs refused to start after VLAN configuration — QEMU exit code 1](incidents/incident-04-vlan-proxmox-crash.md) | Proxmox 9.1.1 introduced strict validation requiring a physical or dummy port on VLAN-aware bridges | Kernel dummy interface workaround; fully documented in `/etc/network/interfaces` with comments |

---

## Key Design Decisions

**Zero-trust VLAN segmentation**
Four isolated VLANs with deny-by-default firewall rules on pfSense. The DMZ (centos-vm1)
has zero access to Management, Services, or Storage — lateral movement after a web app
compromise is blocked before reaching DC01 or the NAS. Each rule is documented with its
threat model justification.

**Self-healing EC2 firewall**
The home ISP assigns dynamic IPs. When it changes, the AWS Security Group becomes stale
and the IPsec tunnel silently dies. `update-sg-ip.sh` runs every 5 minutes on EC2: it queries
DuckDNS for the current home IP, compares it to the live Security Group, and updates all four
restricted ports if there's a mismatch. Also updates Fail2ban's `ignoreip` and restarts the
service. Full infrastructure recovery within ~10 minutes of any IP rotation.

**Write-only IAM for S3 backups**
The backup IAM user (`lab-s3-backup-bot`) has `s3:PutObject` and `s3:ListBucket` only —
no `GetObject`, no `DeleteObject`. If credentials are ever exposed on a compromised VM,
an attacker can overwrite recent backups but cannot delete versioned history. S3 versioning
is enabled; the 7-day lifecycle policy keeps costs under $0.01/month.

**Why IPsec IKEv2 over WireGuard**
IPsec IKEv2 is the enterprise standard for site-to-site VPN — natively supported in pfSense,
all Cisco/Fortinet/Palo Alto hardware, and AWS VPN Gateway. WireGuard is excellent for
individual client VPNs. Choosing IPsec demonstrates familiarity with the technology that
actually appears in job descriptions.

**Why Proxmox over VMware ESXi**
Proxmox VE uses KVM/QEMU — the same hypervisor that powers AWS EC2 instances.
Open source, no licensing cost, mature REST API, and growing adoption in SMEs and MSPs.
Skills transfer directly to cloud environments.

**Centralized backup master pattern**
centos-vm2 acts as backup master: it SSHes into pfSense and centos-vm1 to pull configs,
compresses everything locally, then pushes to S3 in a single job. One IAM credential on
one machine. One cron job to monitor. One log file to check.

---

## Three-Tier Disaster Recovery

| Tier | Media | Location | Scope | Frequency | RTO |
|---|---|---|---|---|---|
| 1 | USB vault (air-gapped EXT4) | On-site | 5 full VM snapshots (.vma.zst) | Manual | ~30 min per VM |
| 2 | AWS S3 (eu-north-1) | Off-site | EC2 configs — NPM, Guacamole, IPsec, Fail2ban | Daily 02:00 | ~20 min |
| 3 | AWS S3 (eu-north-1) | Off-site | On-prem configs — pfSense, CentOS, monitoring stack | Daily 03:00 | ~10 min |

Recovery procedures for each scenario are documented in [`backups/disaster-recovery.md`](backups/disaster-recovery.md).

---

## Skills Demonstrated

| Domain | Technologies |
|---|---|
| Virtualization | Proxmox VE 8, QEMU/KVM, VM lifecycle, VLAN-aware bridges |
| Networking | pfSense, IPsec IKEv2, 802.1Q VLANs, NAT, inter-VLAN routing, zero-trust firewall rules |
| Linux | CentOS Stream 9, Ubuntu 24.04, SELinux, firewalld, systemd, NFS mounts, bash |
| Windows | Windows Server 2022, AD DS, DNS, DHCP, GPO, PowerShell, windows-exporter |
| Cloud — AWS | EC2, VPC, Security Groups, IAM least privilege, S3 versioning + lifecycle, Elastic IP |
| Containers | Docker, Podman, Docker Compose, podman-compose, DOCKER-USER iptables chain |
| Monitoring | Prometheus, Grafana, node-exporter (Linux), windows-exporter (Windows), PromQL |
| Security | Fail2ban, TOTP MFA, AD LDAP, IPsec PSK, DMZ isolation, write-only IAM |
| Backup & DR | 3-2-1 strategy, Proxmox snapshots (.vma.zst), S3 versioning, FinOps lifecycle policies |
| Automation | Bash scripting, cron, AWS CLI, DuckDNS DDNS, self-healing firewall automation |
| Remote Access | Apache Guacamole (clientless RDP/SSH/SFTP), Nginx Proxy Manager, Let's Encrypt SSL |
| Storage | OpenMediaVault, SMB shares, NFS persistent mounts (`_netdev`), EXT4 |

---

## Repository Structure

```
hybrid-cloud-infrastructure-lab/
├── README.md
├── ROADMAP.md                         # Future phases (NPS/RADIUS, AD CS, Ansible, Terraform)
├── PROJECT-STORY.md                   # Build narrative — month by month
├── incidents/
│   ├── incident-01-fail2ban-lockout.md
│   ├── incident-02-ipsec-blackhole.md
│   ├── incident-03-ddns-silent-fail.md
│   └── incident-04-vlan-proxmox-crash.md
├── architecture/
│   ├── architecture-overview.md
│   ├── network-topology.md            # Full IP addressing, VLAN table, routing
│   └── diagrams/
│       └── prometheus-targets.png     # Screenshot — all nodes monitored
├── automation/
│   ├── cron-jobs.md
│   ├── dynamic-dns.md
│   └── update-sg-ip.sh                # Self-healing EC2 Security Group script
├── backups/
│   ├── disaster-recovery.md           # Recovery procedures per scenario
│   ├── s3-backup.sh
│   └── onprem-s3-backup.sh
├── infrastructure/
│   ├── aws/                           # VPC, EC2, IAM policies, Security Group
│   ├── centos/                        # OS hardening, SELinux, firewalld
│   ├── pfsense/                       # Firewall rules, IPsec config, VLAN setup
│   ├── proxmox/                       # network/interfaces, VM startup order
│   └── windows/                       # AD DS setup, DNS, windows-exporter
├── security/
│   ├── fail2ban/                      # jail.local, npm-general filter
│   ├── ldap/                          # Guacamole LDAP integration
│   └── mfa/                           # TOTP setup and enrollment flow
├── services/
│   ├── guacamole/                     # docker-compose.yml, NPM config
│   └── monitoring/                    # prometheus.yml, podman-compose.yml
└── storage/
    └── nas/                           # OMV config, NFS exports, SMB shares
```

---

## Infrastructure at a Glance

| Component | Role | Location | IP | Status |
|---|---|---|---|---|
| Proxmox VE 8 | KVM hypervisor | Dell Latitude E5470 | 192.168.11.50 | Running |
| pfSense CE | Firewall, NAT, IPsec, VLAN routing | VM on Proxmox | WAN: DHCP | Running |
| DC01 — WinSrv 2022 | AD DS, DNS, DHCP, LDAP | VLAN 10 | 192.168.10.10 | Running |
| centos-vm2 | Prometheus, Grafana, backup master | VLAN 20 | 192.168.20.30 | Running |
| centos-vm1 | node-exporter, DMZ workload | VLAN 30 | 192.168.30.20 | Running |
| omv-nas | OpenMediaVault, SMB + NFS | VLAN 40 | 192.168.40.40 | Running |
| EC2 lab-secure-edge | Guacamole, NPM, Fail2ban | AWS eu-north-1 | 51.20.237.223 | Running |
| IPsec tunnel | pfSense ↔ EC2 encrypted link | Overlay | — | Established |

**Hardware constraint:** Everything on-premise runs on 8 GB RAM. Allocation is documented in
[`infrastructure/proxmox/`](infrastructure/proxmox/) — every MB is accounted for.

**AWS cost:** Under $10/month on a $100 credit. S3 lifecycle policy keeps backup storage
below $0.01/month. Documented in [`infrastructure/aws/`](infrastructure/aws/).

---

## How the Authentication Flow Works

A request from any browser in the world to access DC01's desktop:

```
Browser (anywhere)
  │  HTTPS 443 — Let's Encrypt certificate
  ▼
EC2 Elastic IP 51.20.237.223
  │  Nginx Proxy Manager — verifies Host header, terminates SSL
  ▼
Apache Guacamole (Docker, internal network only — port never exposed)
  │  LDAP 389 → IPsec tunnel → DC01 (192.168.10.10) — AD credential check
  │  TOTP — 6-digit code verified against PostgreSQL-stored secret
  ▼
RDP 3389 → IPsec tunnel → DC01
  ▼
Windows Server 2022 desktop in the browser
```

DC01 is never exposed to the internet. LDAP traffic is plaintext on port 389 but travels
entirely inside the AES-256 IPsec tunnel. TOTP is the second factor after AD credentials.

---

## Author

**Aymane Aboukhaira**
Networks & Systems — ISMONTIC, Tangier, Morocco | Graduating 2026
CCNA in progress (expected May 2026)
