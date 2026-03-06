# SMB Share Configuration

## OMV SMB Setup

In OMV Web UI:
1. Services → SMB/CIFS → Enable
2. Shares → Add:
   - Shared folder: lab-share
   - Public: No
   - Browseable: Yes

## User Setup

In OMV: User Management → Add user `aymane` with password. This is the SMB-specific user account (separate from OMV admin).

## Access from Admin Workstation (Windows 11)

Map network drive:
- Path: `\\192.168.40.40\lab-share`
- Username: aymane
- Password: (configured in OMV)

Or via File Explorer → This PC → Map Network Drive → enter UNC path.

## Access via Guacamole (Zero-Trust File Bridge)

From any browser worldwide:
1. Log into Guacamole
2. Open `omv-nas - SSH` connection
3. Press `Ctrl+Shift+Alt` → File Transfer tab
4. Upload/download files via SFTP

This provides internet-accessible file management with no SMB/NFS exposure to the public internet.
