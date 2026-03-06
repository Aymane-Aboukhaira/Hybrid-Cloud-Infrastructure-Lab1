# EC2 Setup — lab-secure-edge

## Instance Specification

| Parameter | Value |
|---|---|
| Name | lab-secure-edge |
| AMI | Ubuntu 24.04 LTS |
| Instance type | t3.micro (1 vCPU, 1GB RAM) |
| Storage | 20GB gp3 |
| Elastic IP | 51.20.237.223 |
| Key pair | lab-key1.pem |
| Security group | lab-secure-edge-sg |

## Why t3.micro?

Free tier eligible. The workload (NPM + Guacamole + PostgreSQL + guacd) fits within 1GB RAM with a 2GB swapfile to handle burst traffic.

## Initial Setup

```bash
# SSH to EC2
ssh -i "lab-key1.pem" ubuntu@51.20.237.223

# Update system
sudo apt update && sudo apt upgrade -y

# Install Docker
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker ubuntu

# Install Docker Compose
sudo apt install -y docker-compose-plugin

# Install strongSwan (IPsec)
sudo apt install -y strongswan strongswan-pki libcharon-extra-plugins

# Install AWS CLI (snap)
sudo snap install aws-cli --classic

# Install dig (DNS lookup for IP automation)
sudo apt install -y dnsutils
```

## Memory Management

t3.micro has 1GB RAM. The Docker stack (NPM + Guacamole + PostgreSQL + guacd) can consume ~700-800MB under load. A swapfile prevents OOM kills:

```bash
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile      # Security: only root can read swap
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

## SSH Access

```bash
ssh -i "D:\migrated data\ISO\lab-key1.pem" ubuntu@51.20.237.223
```

If SSH times out: home IP changed. Check `/var/log/update-sg-ip.log` to see if auto-update ran. Otherwise update Security Group manually via AWS Console or CloudShell.
