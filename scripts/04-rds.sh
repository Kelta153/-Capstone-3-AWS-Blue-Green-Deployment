#!/usr/bin/env bash

set -euo pipefail

############################################
# Blue-Green Deployment Capstone
# Script: 04-rds.sh
# Purpose: Create MySQL RDS Instance
############################################

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

source resource.env

############################################
# Validate required variables
############################################

: "${PRIVATE_SUBNET_A:?Missing PRIVATE_SUBNET_A}"
: "${PRIVATE_SUBNET_B:?Missing PRIVATE_SUBNET_B}"
: "${RDS_SG:?Missing RDS_SG}"

############################################
# Database Configuration
############################################

DB_SUBNET_GROUP="BlueGreen-DBSubnetGroup"

DB_IDENTIFIER=${DB_IDENTIFIER:-bluegreen-db}

DB_NAME=${DB_NAME:-bluegreen}

DB_USERNAME=${DB_USERNAME:-admin}

DB_PASSWORD=${DB_PASSWORD:?Please export DB_PASSWORD before running this script.}

############################################
# Create DB Subnet Group
############################################

echo "Creating DB Subnet Group..."

aws rds create-db-subnet-group \
--db-subnet-group-name "$DB_SUBNET_GROUP" \
--db-subnet-group-description "Blue Green Deployment DB Subnet Group" \
--subnet-ids "$PRIVATE_SUBNET_A" "$PRIVATE_SUBNET_B"

############################################
# Launch RDS
############################################

echo "Creating MySQL RDS Instance..."

aws rds create-db-instance \
--db-instance-identifier "$DB_IDENTIFIER" \
--engine mysql \
--engine-version 8.0 \
--db-instance-class db.t3.micro \
--allocated-storage 20 \
--storage-type gp3 \
--master-username "$DB_USERNAME" \
--master-user-password "$DB_PASSWORD" \
--db-name "$DB_NAME" \
--vpc-security-group-ids "$RDS_SG" \
--db-subnet-group-name "$DB_SUBNET_GROUP" \
--backup-retention-period 7 \
--publicly-accessible false \
--no-multi-az

echo
echo "Waiting for RDS instance..."

aws rds wait db-instance-available \
--db-instance-identifier "$DB_IDENTIFIER"

############################################
# Retrieve Endpoint
############################################

RDS_ENDPOINT=$(aws rds describe-db-instances \
--db-instance-identifier "$DB_IDENTIFIER" \
--query "DBInstances[0].Endpoint.Address" \
--output text)

############################################
# Save Resources
############################################

cat >> resource.env <<EOF

DB_IDENTIFIER=$DB_IDENTIFIER
DB_SUBNET_GROUP=$DB_SUBNET_GROUP
DB_ENDPOINT=$RDS_ENDPOINT
DB_NAME=$DB_NAME
DB_USERNAME=$DB_USERNAME

EOF

echo
echo "========================================"
echo "RDS Deployment Complete"
echo "========================================"

echo "Endpoint : $RDS_ENDPOINT"