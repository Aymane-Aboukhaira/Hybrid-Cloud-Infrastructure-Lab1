# Network Topology

## IP Address Plan

### Home Network (ISP-assigned)
| Device | IP | Role |
|---|---|---|
| Home Router | 192.168.11.1 | Default gateway |
| Proxmox VE | 192.168.11.50 | Hypervisor management |
| pfSense WAN | 192.168.11.x (DHCP) | Lab gateway uplink |
| Admin Workstation | 192.168.11.x (WiFi) | Management access |

### Lab VLANs (post-segmentation)
| VLAN | Subnet | Gateway | DNS | Hosts |
|---|---|---|---|---|
| VLAN 10 (MGMT) | 192.168.10.0/24 | 192.168.10.1 | 192.168.10.10 (DC01) | DC01: .10 |
| VLAN 20 (SERVICES) | 192.168.20.0/24 | 192.168.20.1 | 192.168.10.10 | centos-vm2: .30 |
| VLAN 30 (DMZ) | 192.168.30.0/24 | 192.168.30.1 | 8.8.8.8 | centos-vm1: .20 |
| VLAN 40 (STORAGE) | 192.168.40.0/24 | 192.168.40.1 | 192.168.10.10 | omv-nas: .40 |

### AWS
| Resource | Value |
|---|---|
| VPC | 10.0.0.0/16 |
| Subnet | 10.0.1.0/24 (eu-north-1a) |
| EC2 Private IP | 10.0.1.99 |
| EC2 Elastic IP | 51.20.237.223 |

---

## Traffic Flow Diagrams

### Admin Browser → Guacamole → DC01 RDP
```
Admin Workstation (192.168.11.x)
    |
    | HTTPS (443)
    v
EC2 Nginx Proxy Manager (51.20.237.223)
    |
    | HTTP (internal Docker bridge: lab-edge-net)
    v
Apache Guacamole container
    |
    | LDAP (389) via IPsec tunnel → DC01 (192.168.10.10) [AUTH]
    |
    | RDP (3389) via IPsec tunnel → DC01 (192.168.10.10) [SESSION]
    v
Windows Server 2022 Desktop in browser
```

### On-Prem VM → S3 Backup
```
centos-vm2 (192.168.20.30)
    |
    | SSH pull from centos-vm1 (192.168.30.20)
    | SCP pull from pfSense (192.168.10.1)
    |
    | AWS CLI s3 cp (outbound internet via pfSense NAT)
    | → through IPsec tunnel → EC2 → S3
    v
s3://aymane-lab-backups/on-prem/
```

### Dynamic IP Self-Healing
```
Home ISP changes public IP
    |
    | centos-vm2 cron (*/5 min):
    | curl duckdns.org/update?ip=<current_ip>
    |
    v
DuckDNS record updated: aymane-lab.duckdns.org → new IP
    |
    | EC2 cron (*/5 min):
    | dig +short aymane-lab.duckdns.org → new IP
    | compare to current SG rule → mismatch detected
    |
    v
EC2 AWS CLI: revoke old IP, authorize new IP
    + update Fail2ban ignoreip
    + log to /var/log/update-sg-ip.log
```

---

## pfSense Bridge and VLAN Configuration

```
Proxmox Host
├── vmbr0 ─── nic0 (physical, 192.168.11.x)
│                └── pfSense vtnet0 (WAN)
│
└── vmbr1 ─── dummy0 (kernel dummy interface)
    [VLAN-aware]
         └── pfSense vtnet1 (LAN trunk)
                  ├── vtnet1.10 → VLAN 10 (192.168.10.1/24)
                  ├── vtnet1.20 → VLAN 20 (192.168.20.1/24)
                  ├── vtnet1.30 → VLAN 30 (192.168.30.1/24)
                  └── vtnet1.40 → VLAN 40 (192.168.40.1/24)
```

Each VM is configured with:
- Bridge: vmbr1
- VLAN tag: 10 / 20 / 30 / 40 (set in Proxmox VM network settings)

---

## Routing Table (pfSense)

| Destination | Gateway | Interface | Description |
|---|---|---|---|
| 0.0.0.0/0 | 192.168.11.1 | WAN | Default route to internet |
| 192.168.10.0/24 | — | VLAN10 | Management network |
| 192.168.20.0/24 | — | VLAN20 | Services network |
| 192.168.30.0/24 | — | VLAN30 | DMZ network |
| 192.168.40.0/24 | — | VLAN40 | Storage network |
| 10.0.0.0/16 | — | IPsec | AWS VPC via tunnel |

---

## IPsec Tunnel Parameters

| Parameter | pfSense (Initiator) | EC2 strongSwan (Responder) |
|---|---|---|
| Mode | auto=start | auto=add |
| Remote ID | 51.20.237.223 | right=%any |
| Local subnet | 192.168.x.0/24 per VLAN | left=10.0.1.99 |
| Remote subnet | 10.0.0.0/16 | rightsubnet=192.168.x.0/24 |
| DPD action | restart | clear |
| NAT-T | Enabled | Enabled |
| IKE version | IKEv2 | IKEv2 |
| Encryption | AES-256 | AES-256 |
| Hash | SHA-256 | SHA-256 |
| DH Group | 14 (MODP2048) | MODP2048 |
| PFS | Disabled | Disabled |

---

## DNS Architecture

| Zone | Server | Purpose |
|---|---|---|
| lab.local | DC01 (192.168.10.10) | Internal domain resolution |
| External | 8.8.8.8 / 1.1.1.1 | Internet DNS (via pfSense forwarder) |
| DMZ (VLAN 30) | 8.8.8.8 direct | Isolated — no internal DNS access |

DC01 is authoritative for `lab.local`. All internal VMs (except DMZ) use DC01 as primary DNS, which resolves hostnames like `centos-vm1.lab.local`, `dc01.lab.local`, etc.

---

## Key Ports and Services Reference

| Port | Protocol | Service | Location |
|---|---|---|---|
| 22 | TCP | SSH | All Linux VMs + EC2 |
| 80 | TCP | HTTP (redirect) | EC2 NPM |
| 81 | TCP | NPM Admin | EC2 (home IP only) |
| 443 | TCP | HTTPS | EC2 NPM |
| 389 | TCP | LDAP | DC01 |
| 500 | UDP | IPsec IKE | pfSense ↔ EC2 |
| 3000 | TCP | Grafana | centos-vm2 |
| 3389 | TCP | RDP | DC01 |
| 4500 | UDP | IPsec NAT-T | pfSense ↔ EC2 |
| 9090 | TCP | Prometheus | centos-vm2 |
| 9100 | TCP | node-exporter | centos-vm1, centos-vm2 |
| 9182 | TCP | windows-exporter | DC01 |
