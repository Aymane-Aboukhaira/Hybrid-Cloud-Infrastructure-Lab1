# Security Groups

## lab-secure-edge-sg

| Port | Protocol | Source | Purpose |
|---|---|---|---|
| 80 | TCP | 0.0.0.0/0 | HTTP (NPM redirect to HTTPS) |
| 443 | TCP | 0.0.0.0/0 | HTTPS (Guacamole via NPM) |
| 22 | TCP | Home IP/32 | SSH admin access |
| 81 | TCP | Home IP/32 | NPM admin panel |
| 500 | UDP | Home IP/32 | IPsec IKE |
| 4500 | UDP | Home IP/32 | IPsec NAT-T |

**Design principle**: Ports 22, 81, 500, and 4500 are restricted to the home IP. This is enforced automatically — `update-sg-ip.sh` rotates the allowed IP when the dynamic home IP changes.

**Why not open IPsec to 0.0.0.0/0?** Although strongSwan requires the correct PSK to establish a tunnel, restricting UDP 500/4500 to the known home IP eliminates an entire class of IKE protocol exploits and brute-force attempts at the perimeter before they reach the software stack.

## Outbound Rules

All outbound traffic is allowed (default). This enables:
- EC2 → S3 (backup uploads)
- EC2 → DuckDNS API (DNS resolution)
- EC2 → AWS APIs (Security Group updates)
- IPsec tunnel responses back to pfSense
