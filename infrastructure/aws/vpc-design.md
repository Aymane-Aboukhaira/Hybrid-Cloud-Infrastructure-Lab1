# AWS VPC Design

## Overview

A dedicated VPC isolates the lab cloud infrastructure from any default AWS resources. All EC2 instances and future services deploy within this VPC.

## VPC Configuration

| Resource | Name | Value |
|---|---|---|
| VPC | lab-vpc | 10.0.0.0/16 |
| Subnet | lab-public-subnet | 10.0.1.0/24 (eu-north-1a) |
| Internet Gateway | lab-igw | Attached to lab-vpc |
| Route Table | lab-public-rt | 0.0.0.0/0 → lab-igw |

## Why eu-north-1 (Stockholm)?

Lowest latency from Morocco within the AWS free tier regions. ~50-80ms RTT from Tangier to Stockholm vs ~120ms to US regions.

## Subnet Design

A single public subnet is used for simplicity. Future iterations would add a private subnet for databases and internal services, with a NAT Gateway for outbound-only internet access.

## Setup Commands

```bash
# Create VPC
aws ec2 create-vpc --cidr-block 10.0.0.0/16 --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=lab-vpc}]'

# Create subnet
aws ec2 create-subnet --vpc-id vpc-XXXX --cidr-block 10.0.1.0/24 --availability-zone eu-north-1a

# Create and attach Internet Gateway
aws ec2 create-internet-gateway --tag-specifications 'ResourceType=internet-gateway,Tags=[{Key=Name,Value=lab-igw}]'
aws ec2 attach-internet-gateway --internet-gateway-id igw-XXXX --vpc-id vpc-XXXX

# Create route table and add default route
aws ec2 create-route-table --vpc-id vpc-XXXX
aws ec2 create-route --route-table-id rtb-XXXX --destination-cidr-block 0.0.0.0/0 --gateway-id igw-XXXX
aws ec2 associate-route-table --route-table-id rtb-XXXX --subnet-id subnet-XXXX
```
