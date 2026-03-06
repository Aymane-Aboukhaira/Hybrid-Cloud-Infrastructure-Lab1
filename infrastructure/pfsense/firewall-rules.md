# pfSense Firewall Rules

## VLAN Inter-Network Access Policy

### Design Principle
Default-deny with explicit allow. Traffic is blocked unless a rule explicitly permits it.

### MGMT (VLAN 10) Rules
| Action | Source | Destination | Purpose |
|---|---|---|---|
| Pass | MGMT net | Any | Administrators need unrestricted access |

### SERVICES (VLAN 20) Rules
| Action | Source | Destination | Purpose |
|---|---|---|---|
| Pass | SERVICES net | Any | Monitoring needs to reach all VMs (Prometheus scraping) |

### DMZ (VLAN 30) Rules
| Action | Source | Destination | Purpose |
|---|---|---|---|
| Block | DMZ net | 192.168.10.0/24 | Block DMZ → Management (prevent DC01 access) |
| Block | DMZ net | 192.168.20.0/24 | Block DMZ → Services (prevent monitoring access) |
| Block | DMZ net | 192.168.40.0/24 | Block DMZ → Storage (prevent NAS access) |
| Block | DMZ net | LAN net | Block DMZ → flat LAN (legacy rule) |
| Pass | DMZ net | Any | Allow internet access for web app |

**Security rationale for DMZ isolation**: centos-vm1 will host a public-facing web application. If the web app is compromised via a vulnerability (SQL injection, RCE, etc.), the attacker should be contained within VLAN 30. They cannot reach DC01 (lateral movement to AD), omv-nas (data exfiltration), or centos-vm2 (disable monitoring). The DMZ can only communicate with the internet.

### STORAGE (VLAN 40) Rules
| Action | Source | Destination | Purpose |
|---|---|---|---|
| Pass | MGMT net | STORAGE net | Admins can manage NAS |
| Pass | SERVICES net | STORAGE net | centos-vm2 backup script can reach NAS |
| Block | Any | STORAGE net | Block all other access to storage |

## IPsec Interface Rules
| Action | Source | Destination | Purpose |
|---|---|---|---|
| Pass | 10.0.0.0/16 | VLAN subnets | Allow EC2/VPC traffic into lab |

## WAN Rules
Default block all inbound. pfSense does not expose any services on the WAN interface directly.
