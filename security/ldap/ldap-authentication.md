# AD LDAP Authentication

## Integration Overview

Guacamole authenticates users against Active Directory via LDAP. The LDAP traffic flows through the IPsec tunnel — DC01 is never directly exposed to the internet.

```
Browser → HTTPS → Guacamole (EC2) → LDAP (389) via IPsec → DC01 (192.168.10.10)
```

## Configuration (docker-compose.yml environment variables)

```yaml
LDAP_HOSTNAME: 192.168.10.10      # DC01 IP (VLAN 10 Management)
LDAP_PORT: 389                     # Standard LDAP (not LDAPS — internal tunnel)
LDAP_USER_BASE_DN: CN=Users,DC=lab,DC=local
LDAP_USERNAME_ATTRIBUTE: sAMAccountName   # Windows login name attribute
```

## Why Not LDAPS (636)?

LDAP on port 389 is used because:
1. Traffic is already encrypted inside the IPsec tunnel (AES-256)
2. AD CS (internal CA) is not yet deployed — no valid cert for LDAPS
3. LDAPS will be configured in Phase 4 once AD CS issues internal certs

## Testing LDAP Connectivity

From inside the Guacamole container:
```bash
docker exec -it guacamole bash
apt install -y ldap-utils
ldapsearch -x -H ldap://192.168.10.10 -D "Administrator@lab.local" \
    -W -b "CN=Users,DC=lab,DC=local" "(sAMAccountName=Administrator)"
```

Should return the Administrator AD object.

## Planned Phase 2 — RADIUS Upgrade

NPS (Network Policy Server) will be installed on DC01. RADIUS replaces LDAP as the authentication protocol for Guacamole, pfSense, and Proxmox. Benefits:
- Industry-standard protocol used by all enterprise network devices
- Supports accounting (login/logout events logged in Windows Event Viewer)
- No direct LDAP directory exposure
- Single auth backend for all infrastructure components
