# Infrastructure Design Document
**Project:** Hybrid Cloud Infrastructure Lab
**Author:** Aymane Aboukhaira
**Version:** 2.0
**Date:** March 2026

---

## 1. Executive Summary

This document describes the design and implementation of a hybrid cloud infrastructure that bridges an on-premise virtualized lab environment with AWS cloud services via an encrypted site-to-site VPN. The infrastructure demonstrates enterprise patterns including network segmentation, zero-trust access control, centralized identity management, multi-layer security, automated operations, and a three-tier disaster recovery strategy.

The system is built on commodity hardware (8GB RAM laptop) running Proxmox VE 8, connected to AWS EC2 via IPsec IKEv2, with Apache Guacamole providing clientless remote access authenticated against Active Directory with TOTP MFA.

---

## 2. Design Requirements

### Functional Requirements
- Remote access to all lab VMs from any browser worldwide
- Encrypted site-to-site connectivity between on-premise and AWS
- Centralized identity management via Active Directory
- Infrastructure monitoring with metrics and dashboards
- Persistent network-attached storage accessible from multiple VMs
- Automated backup and disaster recovery capability

### Non-Functional Requirements
- All credentials protected by MFA
- No direct internet exposure of on-premise services
- Dynamic home IP handled automatically (no manual intervention)
- Infrastructure recoverable from complete hardware failure
- AWS spend under $10/month (within $100 credit budget)

### Constraints
- Single physical machine with 8GB RAM
- No hardware purchases permitted
- AWS Free Tier / credit budget only
- Must be demonstrable in a job interview context

---

## 3. Architecture Decisions

### 3.1 Hypervisor Choice: Proxmox VE

**Decision**: Proxmox VE 8 over VMware ESXi or Hyper-V.

**Rationale**:
- Open source — no licensing cost
- KVM-based — industry-standard hypervisor technology
- VLAN-aware bridges — native 802.1Q support
- Backup API — programmatic VM snapshots via CLI
- Active community and enterprise adoption (used in SMBs and MSPs)

### 3.2 Firewall Choice: pfSense

**Decision**: pfSense CE over OPNsense or a Linux-based firewall.

**Rationale**:
- Industry-standard for lab and SMB environments
- Native IPsec client/responder with GUI management
- VLAN interface management
- DHCP, DNS resolver, and Dynamic DNS built-in
- Widely documented in professional certifications (relevant for CCNA/network job roles)

### 3.3 VPN Protocol: IPsec IKEv2

**Decision**: IPsec IKEv2 over OpenVPN or WireGuard.

**Rationale**:
- Site-to-site IPsec is the enterprise standard for WAN connectivity
- IKEv2 is more efficient than IKEv1 (fewer round trips, built-in NAT-T)
- AES-256/SHA-256/MODP2048 meets NIST recommendations
- Skills directly transferable to enterprise network roles
- WireGuard, while simpler, is newer and less commonly seen in job requirements

### 3.4 Remote Access: Apache Guacamole

**Decision**: Apache Guacamole over direct VPN client distribution.

**Rationale**:
- Clientless — any browser, any device, zero software installation
- Supports RDP, SSH, VNC, SFTP in a single interface
- Integrates with AD LDAP + TOTP natively
- Mirrors enterprise "jump server" pattern
- Demonstrates container orchestration, reverse proxy, and SSL management

### 3.5 Network Segmentation: VLANs over separate bridges

**Decision**: 802.1Q VLAN tags on a single VLAN-aware bridge over separate Proxmox bridges per network.

**Rationale**:
- Mirrors enterprise switch configuration (trunk ports, VLAN tagging)
- Scales to more VLANs without adding bridges
- pfSense manages all inter-VLAN routing in a single firewall — centralized policy enforcement
- Skills directly applicable to enterprise switching (Cisco CCNA content)

### 3.6 Backup IAM Policy: Write-Only

**Decision**: S3 backup IAM user has `PutObject` + `ListBucket` only — no delete permission.

**Rationale**:
- Defense against ransomware: if credentials are found on a compromised VM, attacker cannot delete backups
- S3 versioning ensures clean previous versions are always recoverable
- Principle of Least Privilege — the backup script never needs to delete objects

---

## 4. Network Design

### 4.1 VLAN Segmentation

| VLAN | Name | Subnet | Purpose | Isolation Level |
|---|---|---|---|---|
| 10 | MGMT | 192.168.10.0/24 | Domain controller, admin access | Full access to all |
| 20 | SERVICES | 192.168.20.0/24 | Monitoring, backup master | Full access to all |
| 30 | DMZ | 192.168.30.0/24 | Web application (future) | Internet only |
| 40 | STORAGE | 192.168.40.0/24 | NAS | MGMT + SERVICES only |

### 4.2 Inter-VLAN Policy Matrix

The DMZ is the most restricted segment. A compromised web application in VLAN 30 cannot reach:
- DC01 (lateral movement to domain controller)
- centos-vm2 (disable monitoring/alerting)
- omv-nas (data exfiltration from storage)

The attacker is contained within VLAN 30 with internet access only.

### 4.3 AWS VPC

| Resource | CIDR |
|---|---|
| VPC | 10.0.0.0/16 |
| Public subnet | 10.0.1.0/24 |
| EC2 private IP | 10.0.1.99 |

The /16 VPC CIDR allows future expansion (multiple subnets for private resources, RDS, etc.).

### 4.4 IPsec Tunnel

The tunnel extends the lab network to AWS. This enables:
- Guacamole (EC2) → LDAP (DC01) over private, encrypted channel
- Prometheus (centos-vm2) → all targets including future EC2 monitoring
- S3 backup traffic from centos-vm2 via pfSense NAT (not through tunnel)
- Zero public internet exposure of on-premise services

---

## 5. Security Architecture

### 5.1 Threat Model

| Threat | Mitigation |
|---|---|
| Brute force against Guacamole | Fail2ban (5 failures = 1hr ban) |
| Credential theft | TOTP MFA (stolen password insufficient) |
| Unauthorized SSH access | AWS Security Group (home IP only) |
| Ransomware finding backup credentials | Write-only IAM (cannot delete S3 objects) |
| Compromised web app → lateral movement | VLAN 30 DMZ isolation |
| Dynamic IP change → lockout | Automated DuckDNS + SG update |
| Admin self-lockout via Fail2ban | Home IP whitelisted in ignoreip |
| IPsec tunnel collapse on IP change | Auto-update of SG UDP 500/4500 rules |

### 5.2 Three-Layer Access Control

```
Layer 1: AWS Security Group
  └── Restricts who can reach EC2 at the network level
  └── SSH/admin/IPsec: home IP only
  └── Auto-updated when dynamic IP changes

Layer 2: Fail2ban
  └── Rate-limits access attempts at application layer
  └── Reads NPM logs (real IPs, not Docker internal IPs)
  └── Injects bans into DOCKER-USER chain

Layer 3: TOTP + AD LDAP
  └── Valid domain credentials required (what you know)
  └── TOTP code required (what you have)
  └── No unauthenticated resource access possible
```

---

## 6. Disaster Recovery Design

### 6.1 Recovery Time Objectives

| Scenario | RTO Target | Recovery Path |
|---|---|---|
| EC2 config loss | 15 min | Restore from S3 Tier 2 |
| On-prem config loss | 20 min | Restore from S3 Tier 3 |
| Single VM failure | 30 min | Restore from USB Tier 1 |
| Complete hardware failure | 2-4 hours | New hardware + USB restore |

### 6.2 Backup Schedule

- 02:00 daily: EC2 → S3 (NPM + Guacamole + IPsec + Fail2ban configs)
- 03:00 daily: centos-vm2 → S3 (pfSense XML + CentOS + monitoring configs)
- On-demand: Proxmox → USB (full VM snapshots, manually triggered)

### 6.3 FinOps

S3 lifecycle policy expires objects after 7 days. At typical backup sizes (<50MB/day), monthly S3 cost is under $0.01. Well within the $100 AWS credit budget.

---

## 7. Future Architecture (Planned)

### Phase 2 — NPS/RADIUS
Replace LDAP with RADIUS. NPS on DC01 acts as RADIUS server. All infrastructure authenticates via RADIUS (Guacamole, pfSense admin, Proxmox admin). DC01 becomes a genuine enterprise authentication hub.

### Phase 3 — Internal Mail Server
Postfix + Dovecot + Roundcube on centos-vm2. Internal @lab.local routing. Enables Grafana alerting, Fail2ban notifications, and Guacamole login alerts via email.

### Phase 4 — AD Certificate Services
Internal CA on DC01. Issues TLS certificates to all internal services. Eliminates self-signed cert warnings. Enables LDAPS (encrypted LDAP on port 636).

### Month 5 — Automation
- Ansible: idempotent playbooks for all VM provisioning
- Terraform: entire AWS infrastructure as code
- GitHub Actions: CI/CD for web application deployment to VLAN 30
- Loki: centralized log aggregation alongside Prometheus
