# Project Story — From Zero to Hybrid Cloud

*The honest account of building a production-grade hybrid cloud lab on an 8GB laptop, a free AWS account, and a lot of troubleshooting.*

---

## Why I Built This

I'm studying Networks & Systems at ISMONTIC in Tangier, Morocco. Like most students, I had theoretical knowledge of Active Directory, VPNs, and cloud infrastructure — but I'd never actually built any of it end-to-end. I decided to change that.

The goal wasn't to follow a tutorial. It was to build something I could genuinely defend in a job interview — something that would break in interesting ways and force me to think like an engineer.

I had two laptops, an AWS free tier account, and four months.

---

## Month 1 — Building the Foundation

The first challenge was the hardware. My "server" was an old Dell Latitude E5470 with an Intel i5 6th gen and 8GB RAM. I installed Proxmox VE 8 bare metal and immediately hit the first real problem: the Intel I219-LM ethernet adapter was failing to auto-negotiate under Linux, dropping the network intermittently.

The fix required manually forcing 100Mbps full-duplex in `/etc/network/interfaces` using ethtool. Not glamorous, but it taught me that enterprise infrastructure is full of hardware quirks that documentation doesn't cover.

I set up pfSense as a VM acting as a dual-homed firewall — WAN facing the home network, LAN providing an isolated lab subnet (192.168.1.0/24). This separation meant I could experiment aggressively without affecting the home network.

Then came Active Directory. Windows Server 2022 on 2GB RAM is tight, but it ran. I configured AD DS, DNS for the lab.local domain, and DHCP. Getting a CentOS VM to authenticate against AD and resolve lab.local DNS was the first real integration win.

The monitoring stack was next. I deployed Prometheus and Grafana on centos-vm2 using podman-compose, added node-exporter on centos-vm1, and configured Windows Exporter on DC01. Watching all three Prometheus targets go green for the first time — that was the moment the project felt real.

---

## Month 2 — Storage and NAS

Month 2 was about persistent storage. I deployed OpenMediaVault on a 1GB RAM VM with a 30GB virtual disk. The goal was an SMB share accessible from my Windows workstation and an NFS share mounted persistently on centos-vm1.

The NFS mount required learning about `/etc/fstab` persistence, NFS version negotiation, and how to properly configure OMV's network permissions to allow specific subnets. It's the kind of work that nobody teaches in class but every sysadmin encounters on day one.

---

## Month 3 — Taking It to the Cloud

This is where the project became genuinely interesting.

I provisioned an AWS EC2 instance (Ubuntu 24.04, t3.micro) and built an IPsec site-to-site VPN between pfSense and EC2's strongSwan. This required understanding the asymmetric nature of NAT traversal — pfSense sits behind a residential NAT, so it had to be the initiator, and EC2 had to be the responder with `right=%any` to accept the dynamic home IP.

Getting the tunnel to stay alive through a residential NAT required a keep-alive mechanism: pfSense pings the EC2 private IP every 10 seconds to prevent the NAT state table from expiring.

I deployed Apache Guacamole, Nginx Proxy Manager, and PostgreSQL on EC2 using Docker Compose. NPM handled Let's Encrypt SSL termination. Guacamole authenticated against Active Directory via LDAP — over the IPsec tunnel. Suddenly, I could open a browser anywhere in the world and get an RDP session to my Windows Server.

Then I added TOTP MFA. Then Fail2ban with custom regex matching NPM access logs, injected into Docker's DOCKER-USER iptables chain (the only chain Docker doesn't bypass). The security stack was three layers deep.

### The Incidents

No real infrastructure project is complete without incidents. I had four.

**The Fail2ban NAT lockout**: I tested Fail2ban by generating 5 failed requests from my workstation. My workstation and pfSense share the same public IP via home NAT. Fail2ban banned that IP, dropped the IPsec UDP packets, and collapsed the tunnel. I had to reach EC2 via AWS CloudShell to unban myself and whitelist the home IP.

**The IPsec blackhole**: My ISP changed my public IP. strongSwan's `right=%any` accepted any initiator IP, but the AWS Security Group still only allowed the old IP for UDP 500/4500. The packets were silently dropped at the AWS perimeter. First troubleshooting step for any silent VPN failure: verify your Security Group matches your current public IP.

**The DDNS glitch**: pfSense's Dynamic DNS client silently failed to update DuckDNS on an IP change. I moved the DuckDNS update to a cron job on centos-vm2 and built a self-healing script on EC2 that queries DuckDNS every 5 minutes and automatically updates the Security Group if the IP changed.

**The Proxmox VLAN crash**: When I started Phase 1 (VLAN segmentation), assigning a VLAN tag to a VM on a virtual bridge with no physical NIC caused QEMU to panic with exit code 1. Proxmox's bridge validation script requires a physical or dummy interface. I injected a kernel dummy interface (`modprobe dummy`) via `/etc/network/interfaces` hooks, bound it to the bridge, and the VMs booted successfully.

---

## The Enterprise Pivot

After presenting the project to my professor, I received critical feedback: the flat 192.168.1.0/24 network was a security vulnerability. If centos-vm1 hosted a web app and was compromised, an attacker would have direct LAN access to the domain controller and NAS.

This led to the four-phase enterprise hardening plan:

**Phase 1 — VLAN Segmentation**: Four isolated networks. DMZ blocks all access to management and storage. pfSense enforces strict inter-VLAN rules.

**Phase 2 — NPS/RADIUS**: Replace LDAP with RADIUS authentication via Windows NPS, making DC01 genuinely productive as an enterprise auth hub.

**Phase 3 — Mail Server**: Internal SMTP relay (Postfix/Dovecot/Roundcube) for @lab.local addresses, enabling real alert emails from Grafana, Fail2ban, and Guacamole.

**Phase 4 — AD CS**: Internal Certificate Authority on DC01, issuing real TLS certificates to all internal services. No more self-signed cert warnings.

---

## What I Learned

The technical skills are obvious from the repository. What I want to highlight are the less obvious lessons:

**Documentation is infrastructure.** The first time EC2 lost connectivity because of a dynamic IP change, I spent an hour diagnosing. The second time, I had the procedure memorized. By the third time, I had automated it. Every incident taught me something that I wrote down.

**Security has layers.** AWS Security Group + Fail2ban + TOTP isn't redundancy for its own sake. Each layer has a different failure mode. Security Groups fail if the IP drifts. Fail2ban fails if the attacker has a different IP than the admin. TOTP fails if credentials are compromised. Together, they're resilient.

**The "why" matters more than the "how."** Any tutorial can show you how to configure an IPsec tunnel. Understanding *why* the initiator and responder have asymmetric configs for NAT traversal — that's what lets you debug it at 2AM when it breaks.

**Constraints drive creativity.** 8GB RAM forced me to make real architectural decisions about which VMs run simultaneously. A $100 AWS credit forced me to think about FinOps — lifecycle policies, write-only IAM, 7-day S3 expiry. Constraints are a feature, not a bug.

---

## What's Next

VLAN migration is completing now. Then NPS/RADIUS, an internal mail server, and AD CS. After that: Ansible to make the entire lab reproducible from a single command, Terraform to codify the AWS infrastructure, and a CI/CD pipeline to deploy applications to the DMZ.

The lab is never finished. That's the point.
