#!/usr/bin/env bash

set -euo pipefail

############################################
# Blue-Green Deployment Capstone
# Script: 06-health-check.sh
#
# Purpose:
#   • Verify Target Health
#   • Shift Traffic
#   • Verify Listener
#   • Demonstrate Canary Deployment
############################################

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

source resource.env

############################################

set_weights () {

BLUE_WEIGHT=$1
GREEN_WEIGHT=$2

cat > configs/listener-config.json <<EOF
[
  {
    "Type":"forward",
    "ForwardConfig":{
      "TargetGroups":[
        {
          "TargetGroupArn":"$BLUE_TG_ARN",
          "Weight":$BLUE_WEIGHT
        },
        {
          "TargetGroupArn":"$GREEN_TG_ARN",
          "Weight":$GREEN_WEIGHT
        }
      ]
    }
  }
]
EOF

aws elbv2 modify-listener \
--listener-arn "$LISTENER_ARN" \
--default-actions file://configs/listener-config.json >/dev/null

echo
echo "Traffic Updated"
echo "Blue  : $BLUE_WEIGHT%"
echo "Green : $GREEN_WEIGHT%"
echo

}

############################################

show_health () {

echo
echo "======================================="
echo "Blue Target"
echo "======================================="

aws elbv2 describe-target-health \
--target-group-arn "$BLUE_TG_ARN" \
--query "TargetHealthDescriptions[*].[Target.Id,TargetHealth.State]" \
--output table

echo
echo "======================================="
echo "Green Target"
echo "======================================="

aws elbv2 describe-target-health \
--target-group-arn "$GREEN_TG_ARN" \
--query "TargetHealthDescriptions[*].[Target.Id,TargetHealth.State]" \
--output table

}

############################################

show_listener () {

echo
echo "======================================="
echo "Current Listener"
echo "======================================="

aws elbv2 describe-listeners \
--listener-arns "$LISTENER_ARN" \
--query "Listeners[0].DefaultActions[0].ForwardConfig.TargetGroups[*].[Weight]" \
--output table

}

############################################

echo
echo "Waiting for Targets..."

aws elbv2 wait target-in-service \
--target-group-arn "$BLUE_TG_ARN" \
--targets Id="$BLUE_INSTANCE_ID"

aws elbv2 wait target-in-service \
--target-group-arn "$GREEN_TG_ARN" \
--targets Id="$GREEN_INSTANCE_ID"

############################################

show_health

############################################
# Blue 100%
############################################

echo
echo "Deploy Stage 1"
echo "Blue 100%"

set_weights 100 0

show_listener

read -p "Press ENTER for Canary Deployment..."

############################################
# Canary
############################################

echo
echo "Deploy Stage 2"
echo "Blue 90%  Green 10%"

set_weights 90 10

show_listener

read -p "Press ENTER for 50/50 validation..."

############################################
# Validation
############################################

echo
echo "Deploy Stage 3"
echo "Blue 50%  Green 50%"

set_weights 50 50

show_listener

read -p "Press ENTER for Full Green Deployment..."

############################################
# Green
############################################

echo
echo "Deploy Stage 4"

set_weights 0 100

show_listener

show_health

############################################

echo
echo "======================================="
echo "Deployment Complete"
echo "======================================="

echo
echo "Application"

echo "http://$ALB_DNS"

echo
echo "Traffic"

echo "Blue  : 0%"
echo "Green : 100%"