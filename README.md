# Hybrid Cloud Infrastructure Lab

> **A production-grade hybrid cloud environment built from scratch — on-premise Proxmox hypervisor connected to AWS via IPsec site-to-site VPN, with enterprise authentication, zero-trust network segmentation, centralized monitoring, and a three-tier disaster recovery strategy.**

---

## About This Project

This lab was designed and built as a portfolio project by **Aymane Aboukhaira**, a Networks & Systems engineering student at ISMONTIC (Tangier, Morocco), graduating 2026. The goal was to simulate a real enterprise hybrid cloud environment using commodity hardware and AWS Free Tier credits — demonstrating hands-on skills across networking, Linux/Windows administration, cloud infrastructure, security, and DevOps automation.

Every decision documented here mirrors what a junior DevOps or sysadmin engineer would encounter in a production environment.

---

## Architecture at a Glance

```
[Admin Workstation - Machine 2]
         |
         | HTTPS / SSH
         |
[Proxmox VE 8 - Machine 1 - 192.168.11.50]
         |
         |--- pfSense (Firewall + IPsec VPN Gateway)
         |         WAN: 192.168.11.x | VLAN Trunk (10/20/30/40)
         |         |
         |         |===[ IPsec Site-to-Site VPN — IKEv2/AES-256 ]===
         |                                |
         |                      AWS EC2 lab-secure-edge
         |                      Elastic IP: 51.20.237.223
         |                      |- Nginx Proxy Manager (SSL)
         |                      |- Apache Guacamole (RDP/SSH/SFTP)
         |                      |- Fail2ban (DOCKER-USER chain)
         |                      |- S3 Backups (write-only IAM)
         |
         |--- VLAN 10 - Management (192.168.10.0/24)
         |         DC01 — Windows Server 2022 (AD DS, DNS, DHCP)
         |
         |--- VLAN 20 - Services (192.168.20.0/24)
         |         centos-vm2 — Prometheus + Grafana + node-exporter
         |
         |--- VLAN 30 - DMZ (192.168.30.0/24) [ISOLATED]
         |         centos-vm1 — Future web app (no LAN access)
         |
         |--- VLAN 40 - Storage (192.168.40.0/24)
                   omv-nas — OpenMediaVault (SMB + NFS)
```

---

## Skills Demonstrated

| Domain | Technologies |
|---|---|
| **Virtualization** | Proxmox VE 8, QEMU/KVM, VM lifecycle management |
| **Networking** | pfSense, IPsec IKEv2, VLANs (802.1Q), NAT, firewall rules, inter-VLAN routing |
| **Linux Administration** | CentOS 9, Ubuntu 24.04, SELinux, firewalld, systemd, cron |
| **Windows Administration** | Windows Server 2022, AD DS, DNS, DHCP, GPO, RDP |
| **Cloud (AWS)** | EC2, VPC, Security Groups, IAM (least privilege), S3, Elastic IP |
| **Containers** | Docker, Podman, Docker Compose, podman-compose |
| **Monitoring** | Prometheus, Grafana, node-exporter, windows-exporter |
| **Security** | Fail2ban, TOTP MFA, AD LDAP, IPsec PSK, VLAN isolation, Zero-Trust DMZ |
| **Backup & DR** | 3-tier DR (USB vault + S3 cloud), write-only IAM, lifecycle policies |
| **Automation** | Bash scripting, cron, DuckDNS dynamic IP automation, AWS CLI |
| **Remote Access** | Apache Guacamole (clientless RDP/SSH/SFTP), Nginx Proxy Manager, Let's Encrypt SSL |
| **Storage** | OpenMediaVault, SMB shares, NFS persistent mounts, ext4 |

---

## Repository Structure

```
hybrid-cloud-infrastructure-lab/
├── README.md                          # This file
├── PROJECT-STORY.md                   # Journey narrative
├── architecture/
│   ├── architecture-overview.md       # Component breakdown
│   ├── network-topology.md            # IP addressing, VLANs, routing
│   └── diagrams/                      # Architecture diagram
├── automation/
│   ├── cron-jobs.md                   # All scheduled tasks
│   ├── dynamic-dns.md                 # DuckDNS + AWS SG automation
│   └── update-sg-ip.sh                # Self-healing EC2 firewall script
├── backups/
│   ├── disaster-recovery.md           # 3-tier DR strategy
│   ├── s3-backup.sh                   # EC2 backup script
│   └── onprem-s3-backup.sh            # On-premise backup script
├── documentation/
│   ├── infrastructure-design-document.md
│   └── technical-implementation-report.md
├── infrastructure/
│   ├── aws/                           # VPC, EC2, IAM, Security Groups
│   ├── centos/                        # OS hardening
│   ├── pfsense/                       # Firewall, IPsec, NAT
│   ├── proxmox/                       # Hypervisor config
│   └── windows/                       # Active Directory setup
├── security/
│   ├── fail2ban/                      # Jail configs
│   ├── ldap/                          # AD LDAP integration
│   └── mfa/                           # TOTP setup
├── services/
│   ├── guacamole/                     # Remote access stack
│   └── monitoring/                    # Prometheus + Grafana
└── storage/
    └── nas/                           # OpenMediaVault NAS
```

---

## Key Features

**Zero-Trust Network Architecture**
Four isolated VLANs with strict inter-VLAN firewall rules. The DMZ (centos-vm1/web app) has no direct access to the management or storage networks — lateral movement is blocked at the pfSense layer.

**Self-Healing EC2 Firewall**
A bash script runs every 5 minutes on EC2, queries DuckDNS for the current home IP, and automatically updates the AWS Security Group when the dynamic ISP IP changes. Eliminates manual intervention on IP rotation.

**Three-Tier Disaster Recovery**
- **Tier 1**: Air-gapped USB vault with all 5 VM snapshots (.vma.zst), integrated into Proxmox GUI for one-click restore
- **Tier 2**: Daily EC2 config backup to S3 (Guacamole, NPM, IPsec, Fail2ban configs)
- **Tier 3**: Daily on-premise backup via centralized centos-vm2 — pulls pfSense config.xml, centos-vm1 configs, and local monitoring stack, uploads through IPsec tunnel to S3

**Enterprise Authentication Stack**
Apache Guacamole authenticates against Active Directory via LDAP over the IPsec tunnel. TOTP MFA enforced as a second factor. No passwords transmitted in cleartext.

**Clientless Remote Access**
Full RDP (DC01), SSH + SFTP (centos-vm1, centos-vm2, omv-nas) — all accessible from any browser via Guacamole, protected by HTTPS (Let's Encrypt), AD authentication, and TOTP.

---

## Current Status

| Phase | Description | Status |
|---|---|---|
| Month 1 | Proxmox + pfSense + AD + Monitoring | ✅ Complete |
| Month 2 | OpenMediaVault NAS (SMB + NFS) | ✅ Complete |
| Month 3 | AWS EC2 + IPsec + Guacamole + MFA + Fail2ban + S3 DR | ✅ Complete |
| Phase 1 | VLAN Segmentation + DMZ Isolation | 🔄 In Progress |
| Phase 2 | NPS/RADIUS replacing LDAP | 📋 Planned |
| Phase 3 | Internal Mail Server (@lab.local) | 📋 Planned |
| Phase 4 | AD CS Internal Certificate Authority | 📋 Planned |
| Month 5 | Ansible + Terraform + CI/CD + Loki | 📋 Planned |

---

## Author

**Aymane Aboukhaira**
Networks & Systems — ISMONTIC, Tangier, Morocco
CCNA in progress (expected May 2026)
