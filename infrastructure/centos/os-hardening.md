# CentOS OS Hardening

## Base Configuration Applied to centos-vm1 and centos-vm2

### SELinux
SELinux is left in **enforcing** mode — the default for CentOS 9. This provides mandatory access control on top of standard Linux permissions.

```bash
# Verify SELinux status
getenforce          # Should return: Enforcing
sestatus            # Full status
```

Do not set SELinux to permissive or disabled. If a container or service fails due to SELinux denial, add a targeted policy rather than disabling SELinux globally.

### firewalld
Both CentOS VMs use firewalld with explicit port allowances:

```bash
# View current rules
firewall-cmd --list-all

# centos-vm2 (monitoring) — open only required ports
firewall-cmd --permanent --add-port=9090/tcp    # Prometheus
firewall-cmd --permanent --add-port=9100/tcp    # node-exporter
firewall-cmd --permanent --add-port=3000/tcp    # Grafana
firewall-cmd --reload
```

### SSH Hardening
```bash
# /etc/ssh/sshd_config — recommended settings
PermitRootLogin yes          # Root required for backup scripts; key-only auth enforced
PasswordAuthentication no    # Key-only authentication (planned for Phase 2+)
PubkeyAuthentication yes
X11Forwarding no
MaxAuthTries 3
```

### Time Synchronization
Clock drift causes AWS API failures (`RequestTimeTooSkewed`). chrony is installed and enabled on both CentOS VMs:

```bash
sudo dnf install -y chrony
sudo systemctl enable --now chronyd
sudo chronyc makestep        # Force immediate sync
sudo chronyc tracking        # Verify sync status
```

### QEMU Guest Agent
Enables Proxmox to communicate with the VM for clean shutdown, IP reporting, and snapshot consistency:

```bash
sudo dnf install -y qemu-guest-agent
sudo systemctl enable --now qemu-guest-agent
```

### Container Auto-restart
Podman containers are configured to restart automatically after reboot:

```bash
# Enable podman auto-restart for all containers defined in compose
systemctl enable podman-restart
```
