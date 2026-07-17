#!/usr/bin/env bash

set -euo pipefail

############################################
# Blue-Green Deployment Capstone
# Script: 03-ec2.sh
# Purpose: Create EC2 instances and SSM
############################################

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

source resource.env

KEY_NAME=${KEY_NAME:-BlueGreen-KeyPair}
INSTANCE_TYPE=${INSTANCE_TYPE:-t3.micro}

############################################
# Key Pair
############################################

if ! aws ec2 describe-key-pairs \
--key-names "$KEY_NAME" >/dev/null 2>&1
then

    echo "Creating Key Pair..."

    aws ec2 create-key-pair \
    --key-name "$KEY_NAME" \
    --query KeyMaterial \
    --output text > "${KEY_NAME}.pem"

    chmod 400 "${KEY_NAME}.pem"

else

    echo "Key Pair already exists."

fi

############################################
# Latest Amazon Linux 2023 AMI
############################################

echo "Retrieving latest Amazon Linux AMI..."

AMI_ID=$(MSYS_NO_PATHCONV=1 aws ssm get-parameters \
--names /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 \
--query "Parameters[0].Value" \
--output text)

############################################
# IAM Role for SSM
############################################

ROLE_NAME="BlueGreenEC2SSMRole"
PROFILE_NAME="BlueGreenEC2SSMProfile"

if ! aws iam get-role \
--role-name "$ROLE_NAME" >/dev/null 2>&1
then

aws iam create-role \
--role-name "$ROLE_NAME" \
--assume-role-policy-document file://policies/ec2-trust-policy.json

aws iam attach-role-policy \
--role-name "$ROLE_NAME" \
--policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore

fi

############################################
# Instance Profile
############################################

if ! aws iam get-instance-profile \
--instance-profile-name "$PROFILE_NAME" >/dev/null 2>&1
then

aws iam create-instance-profile \
--instance-profile-name "$PROFILE_NAME"

sleep 10

aws iam add-role-to-instance-profile \
--instance-profile-name "$PROFILE_NAME" \
--role-name "$ROLE_NAME"

sleep 20

fi

############################################
# Launch Blue Instance
############################################

echo "Launching Blue Server..."

BLUE_INSTANCE_ID=$(aws ec2 run-instances \
--image-id "$AMI_ID" \
--count 1 \
--instance-type "$INSTANCE_TYPE" \
--key-name "$KEY_NAME" \
--security-group-ids "$WEB_SG" \
--subnet-id "$PUBLIC_SUBNET_A" \
--iam-instance-profile Name="$PROFILE_NAME" \
--user-data file://userdata/blue.sh \
--tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=Blue-Server},{Key=Environment,Value=Blue},{Key=Project,Value=$PROJECT}]" \
--query "Instances[0].InstanceId" \
--output text)

############################################
# Launch Green Instance
############################################

echo "Launching Green Server..."

GREEN_INSTANCE_ID=$(aws ec2 run-instances \
--image-id "$AMI_ID" \
--count 1 \
--instance-type "$INSTANCE_TYPE" \
--key-name "$KEY_NAME" \
--security-group-ids "$WEB_SG" \
--subnet-id "$PUBLIC_SUBNET_B" \
--iam-instance-profile Name="$PROFILE_NAME" \
--user-data file://userdata/green.sh \
--tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=Green-Server},{Key=Environment,Value=Green},{Key=Project,Value=$PROJECT}]" \
--query "Instances[0].InstanceId" \
--output text)

############################################
# Wait
############################################

echo "Waiting for instances..."

aws ec2 wait instance-running \
--instance-ids \
"$BLUE_INSTANCE_ID" \
"$GREEN_INSTANCE_ID"

############################################
# Public DNS
############################################

BLUE_PUBLIC_DNS=$(aws ec2 describe-instances \
--instance-ids "$BLUE_INSTANCE_ID" \
--query "Reservations[0].Instances[0].PublicDnsName" \
--output text)

GREEN_PUBLIC_DNS=$(aws ec2 describe-instances \
--instance-ids "$GREEN_INSTANCE_ID" \
--query "Reservations[0].Instances[0].PublicDnsName" \
--output text)

############################################
# Save
############################################

cat >> resource.env <<EOF

KEY_NAME=$KEY_NAME
INSTANCE_TYPE=$INSTANCE_TYPE

AMI_ID=$AMI_ID

BLUE_INSTANCE_ID=$BLUE_INSTANCE_ID
GREEN_INSTANCE_ID=$GREEN_INSTANCE_ID

BLUE_PUBLIC_DNS=$BLUE_PUBLIC_DNS
GREEN_PUBLIC_DNS=$GREEN_PUBLIC_DNS
EOF

echo
echo "========================================"
echo "EC2 Infrastructure Ready"
echo "========================================"

echo "Blue Instance : $BLUE_INSTANCE_ID"
echo "Green Instance: $GREEN_INSTANCE_ID"

echo
echo "Blue URL"
echo "http://$BLUE_PUBLIC_DNS"

echo
echo "Green URL"
echo "http://$GREEN_PUBLIC_DNS"