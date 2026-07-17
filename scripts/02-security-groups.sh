#!/usr/bin/env bash

set -euo pipefail

############################################
# Blue-Green Deployment Capstone
# Script: 02-security-groups.sh
# Purpose: Create Security Groups
############################################

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

source resource.env

echo "Creating ALB Security Group..."

ALB_SG=$(aws ec2 create-security-group \
--group-name ALB-SG \
--description "Security Group for Application Load Balancer" \
--vpc-id "$VPC_ID" \
--tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=ALB-SG},{Key=Project,Value=$PROJECT}]" \
--query "GroupId" \
--output text)

echo "Creating WEB Security Group..."

WEB_SG=$(aws ec2 create-security-group \
--group-name WEB-SG \
--description "Security Group for Blue/Green EC2 Instances" \
--vpc-id "$VPC_ID" \
--tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=WEB-SG},{Key=Project,Value=$PROJECT}]" \
--query "GroupId" \
--output text)

echo "Creating RDS Security Group..."

RDS_SG=$(aws ec2 create-security-group \
--group-name RDS-SG \
--description "Security Group for RDS Database" \
--vpc-id "$VPC_ID" \
--tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=RDS-SG},{Key=Project,Value=$PROJECT}]" \
--query "GroupId" \
--output text)

############################################
# ALB Security Group Rules
############################################

echo "Configuring ALB Security Group..."

aws ec2 authorize-security-group-ingress \
--group-id "$ALB_SG" \
--protocol tcp \
--port 80 \
--cidr 0.0.0.0/0

############################################
# WEB Security Group Rules
############################################

echo "Configuring WEB Security Group..."

# HTTP from ALB
aws ec2 authorize-security-group-ingress \
--group-id "$WEB_SG" \
--protocol tcp \
--port 80 \
--source-group "$ALB_SG"

# SSH (used initially before migrating to SSM)
aws ec2 authorize-security-group-ingress \
--group-id "$WEB_SG" \
--protocol tcp \
--port 22 \
--cidr 0.0.0.0/0

# Added during troubleshooting so the EC2 instances
# could be tested directly via their public IPs.
aws ec2 authorize-security-group-ingress \
--group-id "$WEB_SG" \
--protocol tcp \
--port 80 \
--cidr 0.0.0.0/0

############################################
# RDS Security Group Rules
############################################

echo "Configuring RDS Security Group..."

aws ec2 authorize-security-group-ingress \
--group-id "$RDS_SG" \
--protocol tcp \
--port 3306 \
--source-group "$WEB_SG"

############################################
# Save IDs
############################################

cat >> resource.env <<EOF

ALB_SG=$ALB_SG
WEB_SG=$WEB_SG
RDS_SG=$RDS_SG
EOF

echo
echo "========================================"
echo "Security Groups Created"
echo "========================================"

echo "ALB SG : $ALB_SG"
echo "WEB SG : $WEB_SG"
echo "RDS SG : $RDS_SG"