# TOTP MFA Setup

## Overview

Time-based One-Time Password (TOTP) is enforced as a second authentication factor in Guacamole. After entering valid AD credentials, users must enter a 6-digit rotating code from an authenticator app (Google Authenticator, Authy, etc.).

## How TOTP Works with Guacamole

1. User visits `https://guac.51.20.237.223.nip.io`
2. Enters AD domain credentials (username + password)
3. Guacamole validates credentials against DC01 via LDAP
4. If valid, Guacamole prompts for TOTP code
5. User enters 6-digit code from authenticator app
6. If TOTP valid, session is granted

TOTP secrets are stored in the PostgreSQL database (not in AD). The `TOTP_ENABLED: "true"` environment variable in docker-compose.yml activates the extension.

## First-Time Enrollment

On first login after TOTP is enabled:
1. Guacamole displays a QR code
2. Scan with authenticator app
3. Enter the first code to confirm enrollment
4. All subsequent logins require the TOTP code

## Why TOTP + LDAP (not just LDAP)?

LDAP alone means a stolen AD password = full access to every system in the lab (DC01 RDP, all SSH sessions, NAS SFTP). TOTP ensures that credential theft alone is insufficient — the attacker also needs physical access to the enrolled device.

## PostgreSQL Environment Variable Note

A common pitfall: older Guacamole documentation uses `POSTGRES_` prefix for environment variables. Newer versions (1.5+) require `POSTGRESQL_` prefix. Using the wrong prefix causes Guacamole to start but fail to connect to the database, resulting in a blank login screen.

Correct:
```yaml
POSTGRESQL_HOSTNAME: postgres
POSTGRESQL_DATABASE: guacamole_db
```

Incorrect (causes silent failure):
```yaml
POSTGRES_HOSTNAME: postgres    # ← deprecated, ignored
```
