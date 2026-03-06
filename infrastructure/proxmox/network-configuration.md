# Proxmox Network Configuration

## Bridge Layout

```
/etc/network/interfaces (Proxmox host)

# Physical NIC — home network uplink
auto nic0
iface nic0 inet manual
    pre-up ethtool -s nic0 speed 100 duplex full autoneg off

# vmbr0 — WAN bridge (pfSense WAN interface)
auto vmbr0
iface vmbr0 inet static
    address 192.168.11.50/24
    gateway 192.168.11.1
    bridge-ports nic0
    bridge-stp off
    bridge-fd 0

# Kernel dummy interface — required for VLAN-aware bridge on Proxmox 9.1.1
# Without a physical or dummy NIC attached, the pve-bridge script panics
# and VMs assigned a VLAN tag fail to boot (QEMU exit code 1, status 6400)
auto dummy0
iface dummy0 inet manual
    pre-up ip link add dummy0 type dummy || true
    post-down ip link delete dummy0 type dummy || true

# vmbr1 — Internal lab LAN (VLAN trunk)
auto vmbr1
iface vmbr1 inet manual
    bridge-ports dummy0
    bridge-stp off
    bridge-fd 0
    bridge-vlan-aware yes
    bridge-vids 2-4094
```

## NIC Autonegotiation Fix

The Intel I219-LM NIC on this hardware (Dell Latitude E5470) fails to autonegotiate under Linux. Symptoms: ethernet drops intermittently, particularly under load.

**Fix**: Force 100Mbps full duplex via ethtool in the interface pre-up hook:
```
pre-up ethtool -s nic0 speed 100 duplex full autoneg off
```

This runs before the interface comes up on every boot. Do not remove this line.

## VLAN Assignment per VM

Each VM gets the following network settings in Proxmox:
- Bridge: `vmbr1`
- VLAN Tag: 10 / 20 / 30 / 40

pfSense's LAN interface (`vtnet0`) is also on `vmbr1` with no VLAN tag — it receives the full trunk and creates sub-interfaces for each VLAN internally.

## Boot Order Configuration

Configured under each VM → Options → Start/Shutdown Order:

| VM | Order | Startup Delay |
|---|---|---|
| pfSense | 1 | 30s |
| DC01 | 2 | 60s |
| centos-vm1 | 3 | 30s |
| centos-vm2 | 3 | 30s |
| omv-nas | 3 | 30s |

All VMs have "Start at boot" enabled. After a power outage:
1. pfSense starts → DHCP, routing, and NAT available
2. DC01 starts → AD and DNS available  
3. All other VMs start → find their gateway and DNS server ready

## Live Network Reload

After editing `/etc/network/interfaces`, reload without rebooting:
```bash
ifreload -a
```

This is safer than `ifdown/ifup` for production bridges with running VMs.
