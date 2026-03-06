# IPsec Site-to-Site VPN Configuration

## Overview

An IKEv2 site-to-site IPsec tunnel connects the on-premise pfSense firewall to the AWS EC2 instance running strongSwan. This creates a private encrypted channel between the lab network and AWS VPC — all traffic between them (Guacamole → AD LDAP, S3 backups, monitoring) flows through this tunnel.

## Architecture: Why Asymmetric Config

pfSense sits behind a residential NAT — it has a private IP on the home router and a dynamic public IP assigned by the ISP. This creates a specific requirement:

- **pfSense must be the INITIATOR** — it punches outbound through the NAT
- **EC2 must be the RESPONDER** — it listens and accepts the incoming connection

| Parameter | pfSense (Initiator) | EC2 strongSwan (Responder) |
|---|---|---|
| `auto` | `start` | `add` |
| Remote peer | `51.20.237.223` (static) | `right=%any` (dynamic) |
| DPD action | `restart` | `clear` |
| NAT-T | Enabled | Enabled |

## EC2 strongSwan Configuration

### /etc/ipsec.conf
```
config setup
    charondebug="ike 1, knl 1, cfg 0"

conn lab-tunnel
    auto=add
    keyexchange=ikev2
    left=10.0.1.99
    leftid=51.20.237.223
    leftsubnet=10.0.0.0/16
    right=%any
    rightsubnet=192.168.0.0/8
    ike=aes256-sha256-modp2048!
    esp=aes256-sha256!
    dpdaction=clear
    dpddelay=30s
    dpdtimeout=120s
    authby=secret
    type=tunnel
    forceencaps=yes
```

### /etc/ipsec.secrets
```
# Format: <local_id> <remote_id> : PSK "<32-char-base64-key>"
51.20.237.223 %any : PSK "YOUR_32_CHAR_PSK_HERE"
```

Generate a strong PSK:
```bash
openssl rand -base64 32
```

## pfSense Configuration

### Phase 1
- Remote Gateway: `51.20.237.223`
- Authentication: Mutual PSK
- IKE Version: IKEv2
- Encryption: AES-256
- Hash: SHA-256
- DH Group: 14 (2048 bit)
- Lifetime: 28800 seconds

### Phase 2
- Local Network: LAN subnet (or specific VLAN subnets)
- Remote Network: `10.0.0.0/16`
- Protocol: ESP
- Encryption: AES-256
- Hash: SHA-256
- PFS: **Disabled** (must match EC2 `esp=aes256-sha256!`)
- Lifetime: 3600 seconds

### Keep-Alive
Under Advanced Options in the Phase 1 entry, enable a ping to `10.0.1.99` (EC2 private IP). This prevents the residential NAT state table from expiring the UDP 500/4500 flows.

## pfSense Firewall Rule for IPsec Traffic

After the tunnel is up, add a rule on the IPsec interface:
- Action: Pass
- Interface: IPsec
- Source: `10.0.0.0/16`
- Destination: LAN/VLAN subnets
- Description: `Allow AWS VPC to lab`

Without this rule, pfSense blocks all inbound tunnel traffic by default.

## Verification

```bash
# On EC2 — check tunnel status
sudo ipsec statusall

# Expected output includes:
# lab-tunnel[1]: ESTABLISHED ...
# lab-tunnel{1}: INSTALLED, TUNNEL ...

# Test connectivity through tunnel
ping -c 3 192.168.10.10   # DC01 (VLAN 10)
ping -c 3 192.168.20.30   # centos-vm2 (VLAN 20)
ping -c 3 192.168.30.20   # centos-vm1 (VLAN 30)
ping -c 3 192.168.40.40   # omv-nas (VLAN 40)
```

## Troubleshooting

**Silent VPN drops (most common cause):**
Home IP changed. Check Security Group allows current IP for UDP 500/4500.
```bash
dig +short aymane-lab.duckdns.org    # Current home IP per DuckDNS
cat /var/log/update-sg-ip.log         # Last update timestamp
```

**IKE negotiation failure:**
```bash
sudo journalctl -t charon -n 50    # strongSwan IKE logs on EC2
```

**Phase 2 mismatch (most common config error):**
Ensure PFS is disabled on pfSense Phase 2. EC2 uses `esp=aes256-sha256!` (the `!` means strict — no PFS).
