#!/usr/bin/env bash

set -euo pipefail

############################################
# Blue-Green Deployment Capstone
# Script: 07-cloudwatch.sh
# Purpose:
#   - Create SNS Topic
#   - Subscribe Email
#   - Create CloudWatch Alarm
############################################

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

source resource.env

############################################
# Validate
############################################

: "${GREEN_TG_ARN:?Missing GREEN_TG_ARN}"
: "${ALB_ARN:?Missing ALB_ARN}"

EMAIL_ADDRESS=${EMAIL_ADDRESS:?Please export EMAIL_ADDRESS before running this script.}

############################################
# Create SNS Topic
############################################

echo "Creating SNS Topic..."

SNS_TOPIC_ARN=$(aws sns create-topic \
--name BlueGreenDeploymentAlerts \
--query "TopicArn" \
--output text)

############################################
# Subscribe Email
############################################

echo
echo "Subscribing Email..."

aws sns subscribe \
--topic-arn "$SNS_TOPIC_ARN" \
--protocol email \
--notification-endpoint "$EMAIL_ADDRESS"

echo
echo "=================================================="
echo "IMPORTANT"
echo
echo "Open your email and CONFIRM the SNS subscription."
echo "After confirmation press ENTER to continue."
echo "=================================================="

read -r

############################################
# Extract Dimensions
############################################

TARGET_GROUP_DIMENSION=$(echo "$GREEN_TG_ARN" | cut -d: -f6)

LOAD_BALANCER_DIMENSION=$(echo "$ALB_ARN" | cut -d: -f6)

############################################
# Create Alarm
############################################

echo "Creating CloudWatch Alarm..."

aws cloudwatch put-metric-alarm \
--alarm-name GreenTarget-UnHealthyHostCount \
--alarm-description "Rollback Blue-Green deployment if Green becomes unhealthy." \
--metric-name UnHealthyHostCount \
--namespace AWS/ApplicationELB \
--statistic Average \
--period 60 \
--evaluation-periods 1 \
--threshold 1 \
--comparison-operator GreaterThanOrEqualToThreshold \
--treat-missing-data notBreaching \
--dimensions \
Name=TargetGroup,Value="$TARGET_GROUP_DIMENSION" \
Name=LoadBalancer,Value="$LOAD_BALANCER_DIMENSION" \
--alarm-actions "$SNS_TOPIC_ARN"

############################################
# Save Resources
############################################

cat >> resource.env <<EOF

SNS_TOPIC_ARN=$SNS_TOPIC_ARN
CLOUDWATCH_ALARM=GreenTarget-UnHealthyHostCount

EOF

############################################

echo
echo "========================================"
echo "CloudWatch Monitoring Ready"
echo "========================================"

echo

echo "SNS Topic"

echo "$SNS_TOPIC_ARN"

echo

echo "Alarm"

echo "GreenTarget-UnHealthyHostCount"