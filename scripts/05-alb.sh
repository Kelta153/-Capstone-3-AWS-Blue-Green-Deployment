#!/usr/bin/env bash

set -euo pipefail

############################################
# Blue-Green Deployment Capstone
# Script: 05-health-check.sh
# Purpose:
#   - Create ALB
#   - Create Target Groups
#   - Register EC2 Instances
#   - Configure Listener
############################################

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

source resource.env

############################################
# Validate
############################################

: "${VPC_ID:?Missing VPC_ID}"
: "${PUBLIC_SUBNET_A:?Missing PUBLIC_SUBNET_A}"
: "${PUBLIC_SUBNET_B:?Missing PUBLIC_SUBNET_B}"
: "${ALB_SG:?Missing ALB_SG}"
: "${BLUE_INSTANCE_ID:?Missing BLUE_INSTANCE_ID}"
: "${GREEN_INSTANCE_ID:?Missing GREEN_INSTANCE_ID}"

############################################
# Target Groups
############################################

echo "Creating Blue Target Group..."

BLUE_TG_ARN=$(MSYS_NO_PATHCONV=1 aws elbv2 create-target-group \
--name BlueGreen-Blue-TG \
--protocol HTTP \
--port 80 \
--target-type instance \
--vpc-id "$VPC_ID" \
--health-check-protocol HTTP \
--health-check-path "/" \
--health-check-port traffic-port \
--query "TargetGroups[0].TargetGroupArn" \
--output text)

echo "Creating Green Target Group..."

GREEN_TG_ARN=$(MSYS_NO_PATHCONV=1 aws elbv2 create-target-group \
--name BlueGreen-Green-TG \
--protocol HTTP \
--port 80 \
--target-type instance \
--vpc-id "$VPC_ID" \
--health-check-protocol HTTP \
--health-check-path "/" \
--health-check-port traffic-port \
--query "TargetGroups[0].TargetGroupArn" \
--output text)

############################################
# Register Targets
############################################

echo "Registering Blue Instance..."

aws elbv2 register-targets \
--target-group-arn "$BLUE_TG_ARN" \
--targets Id="$BLUE_INSTANCE_ID"

echo "Registering Green Instance..."

aws elbv2 register-targets \
--target-group-arn "$GREEN_TG_ARN" \
--targets Id="$GREEN_INSTANCE_ID"

############################################
# Application Load Balancer
############################################

echo "Creating Application Load Balancer..."

ALB_ARN=$(aws elbv2 create-load-balancer \
--name BlueGreen-ALB \
--type application \
--scheme internet-facing \
--security-groups "$ALB_SG" \
--subnets "$PUBLIC_SUBNET_A" "$PUBLIC_SUBNET_B" \
--query "LoadBalancers[0].LoadBalancerArn" \
--output text)

echo "Waiting for ALB..."

aws elbv2 wait load-balancer-available \
--load-balancer-arns "$ALB_ARN"

############################################
# Listener
############################################

echo "Creating Listener..."

LISTENER_ARN=$(aws elbv2 create-listener \
--load-balancer-arn "$ALB_ARN" \
--protocol HTTP \
--port 80 \
--default-actions Type=forward,TargetGroupArn="$BLUE_TG_ARN" \
--query "Listeners[0].ListenerArn" \
--output text)

############################################
# Weighted Routing
############################################

echo "Configuring Blue/Green Routing..."

mkdir -p configs

cat > configs/listener-config.json <<EOF
[
  {
    "Type": "forward",
    "ForwardConfig": {
      "TargetGroups": [
        {
          "TargetGroupArn": "$BLUE_TG_ARN",
          "Weight": 100
        },
        {
          "TargetGroupArn": "$GREEN_TG_ARN",
          "Weight": 0
        }
      ]
    }
  }
]
EOF

aws elbv2 modify-listener \
--listener-arn "$LISTENER_ARN" \
--default-actions file://configs/listener-config.json

############################################
# Wait for Targets
############################################

echo
echo "Waiting for Blue Target..."

aws elbv2 wait target-in-service \
--target-group-arn "$BLUE_TG_ARN" \
--targets Id="$BLUE_INSTANCE_ID"

echo
echo "Waiting for Green Target..."

aws elbv2 wait target-in-service \
--target-group-arn "$GREEN_TG_ARN" \
--targets Id="$GREEN_INSTANCE_ID"

############################################
# ALB DNS
############################################

ALB_DNS=$(aws elbv2 describe-load-balancers \
--load-balancer-arns "$ALB_ARN" \
--query "LoadBalancers[0].DNSName" \
--output text)

############################################
# Save
############################################

cat >> resource.env <<EOF

BLUE_TG_ARN=$BLUE_TG_ARN
GREEN_TG_ARN=$GREEN_TG_ARN

ALB_ARN=$ALB_ARN
LISTENER_ARN=$LISTENER_ARN
ALB_DNS=$ALB_DNS

EOF

############################################

echo
echo "========================================"
echo "Blue-Green Load Balancer Ready"
echo "========================================"

echo
echo "Application URL"

echo "http://$ALB_DNS"