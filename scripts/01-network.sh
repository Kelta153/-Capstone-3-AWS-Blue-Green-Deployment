#!/usr/bin/env bash

set -euo pipefail

############################################
# Blue-Green Deployment Capstone
# Script: 01-network.sh
# Purpose: Create networking infrastructure
############################################

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

RESOURCE_FILE="resource.env"

touch "$RESOURCE_FILE"

if ! grep -q "^AWS_REGION=" "$RESOURCE_FILE"; then
    echo "AWS_REGION=us-east-1" >> "$RESOURCE_FILE"
fi

source "$RESOURCE_FILE"

PROJECT=${PROJECT:-BlueGreenCapstone}
AWS_REGION=${AWS_REGION:-us-east-1}

echo "Creating VPC..."

VPC_ID=$(aws ec2 create-vpc \
    --cidr-block 10.0.0.0/16 \
    --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=BlueGreen-VPC},{Key=Project,Value=$PROJECT}]" \
    --query "Vpc.VpcId" \
    --output text)

aws ec2 modify-vpc-attribute \
    --vpc-id "$VPC_ID" \
    --enable-dns-support "{\"Value\":true}"

aws ec2 modify-vpc-attribute \
    --vpc-id "$VPC_ID" \
    --enable-dns-hostnames "{\"Value\":true}"

echo "Creating Internet Gateway..."

IGW_ID=$(aws ec2 create-internet-gateway \
    --tag-specifications "ResourceType=internet-gateway,Tags=[{Key=Name,Value=BlueGreen-IGW},{Key=Project,Value=$PROJECT}]" \
    --query "InternetGateway.InternetGatewayId" \
    --output text)

aws ec2 attach-internet-gateway \
    --internet-gateway-id "$IGW_ID" \
    --vpc-id "$VPC_ID"

echo "Creating Public Subnet A..."

PUBLIC_SUBNET_A=$(aws ec2 create-subnet \
    --vpc-id "$VPC_ID" \
    --cidr-block 10.0.1.0/24 \
    --availability-zone "${AWS_REGION}a" \
    --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=Public-Subnet-A},{Key=Project,Value=$PROJECT}]" \
    --query "Subnet.SubnetId" \
    --output text)

echo "Creating Public Subnet B..."

PUBLIC_SUBNET_B=$(aws ec2 create-subnet \
    --vpc-id "$VPC_ID" \
    --cidr-block 10.0.2.0/24 \
    --availability-zone "${AWS_REGION}b" \
    --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=Public-Subnet-B},{Key=Project,Value=$PROJECT}]" \
    --query "Subnet.SubnetId" \
    --output text)

echo "Creating Private Subnet A..."

PRIVATE_SUBNET_A=$(aws ec2 create-subnet \
    --vpc-id "$VPC_ID" \
    --cidr-block 10.0.3.0/24 \
    --availability-zone "${AWS_REGION}a" \
    --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=Private-Subnet-A},{Key=Project,Value=$PROJECT}]" \
    --query "Subnet.SubnetId" \
    --output text)

echo "Creating Private Subnet B..."

PRIVATE_SUBNET_B=$(aws ec2 create-subnet \
    --vpc-id "$VPC_ID" \
    --cidr-block 10.0.4.0/24 \
    --availability-zone "${AWS_REGION}b" \
    --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=Private-Subnet-B},{Key=Project,Value=$PROJECT}]" \
    --query "Subnet.SubnetId" \
    --output text)

echo "Enabling auto-assign public IPs..."

aws ec2 modify-subnet-attribute \
    --subnet-id "$PUBLIC_SUBNET_A" \
    --map-public-ip-on-launch

aws ec2 modify-subnet-attribute \
    --subnet-id "$PUBLIC_SUBNET_B" \
    --map-public-ip-on-launch

echo "Creating Public Route Table..."

PUBLIC_RT=$(aws ec2 create-route-table \
    --vpc-id "$VPC_ID" \
    --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=Public-RouteTable},{Key=Project,Value=$PROJECT}]" \
    --query "RouteTable.RouteTableId" \
    --output text)

echo "Creating Private Route Table..."

PRIVATE_RT=$(aws ec2 create-route-table \
    --vpc-id "$VPC_ID" \
    --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=Private-RouteTable},{Key=Project,Value=$PROJECT}]" \
    --query "RouteTable.RouteTableId" \
    --output text)

aws ec2 create-route \
    --route-table-id "$PUBLIC_RT" \
    --destination-cidr-block 0.0.0.0/0 \
    --gateway-id "$IGW_ID"

aws ec2 associate-route-table \
    --route-table-id "$PUBLIC_RT" \
    --subnet-id "$PUBLIC_SUBNET_A" >/dev/null

aws ec2 associate-route-table \
    --route-table-id "$PUBLIC_RT" \
    --subnet-id "$PUBLIC_SUBNET_B" >/dev/null

aws ec2 associate-route-table \
    --route-table-id "$PRIVATE_RT" \
    --subnet-id "$PRIVATE_SUBNET_A" >/dev/null

aws ec2 associate-route-table \
    --route-table-id "$PRIVATE_RT" \
    --subnet-id "$PRIVATE_SUBNET_B" >/dev/null

cat > "$RESOURCE_FILE" <<EOF
PROJECT=$PROJECT
AWS_REGION=$AWS_REGION

VPC_ID=$VPC_ID
IGW_ID=$IGW_ID

PUBLIC_SUBNET_A=$PUBLIC_SUBNET_A
PUBLIC_SUBNET_B=$PUBLIC_SUBNET_B

PRIVATE_SUBNET_A=$PRIVATE_SUBNET_A
PRIVATE_SUBNET_B=$PRIVATE_SUBNET_B

PUBLIC_RT=$PUBLIC_RT
PRIVATE_RT=$PRIVATE_RT
EOF

echo
echo "========================================"
echo "Network infrastructure created."
echo "========================================"

cat "$RESOURCE_FILE"