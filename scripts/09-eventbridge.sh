#!/usr/bin/env bash

set -euo pipefail

############################################
# Blue-Green Deployment Capstone
# Script: 08-eventbridge.sh
#
# Purpose:
#   • Create EventBridge Rule
#   • Connect Rule to Lambda
#   • Grant Lambda Invoke Permission
############################################

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

source resource.env

############################################
# Validate
############################################

: "${CLOUDWATCH_ALARM:?Missing CLOUDWATCH_ALARM}"
: "${LAMBDA_FUNCTION_NAME:?Missing LAMBDA_FUNCTION_NAME}"
: "${LAMBDA_FUNCTION_ARN:?Missing LAMBDA_FUNCTION_ARN}"

RULE_NAME="BlueGreenRollbackRule"

############################################
# Event Pattern
############################################

mkdir -p configs

cat > configs/eventbridge-pattern.json <<EOF
{
  "source": ["aws.cloudwatch"],
  "detail-type": ["CloudWatch Alarm State Change"],
  "detail": {
    "alarmName": ["$CLOUDWATCH_ALARM"],
    "state": {
      "value": ["ALARM"]
    }
  }
}
EOF

############################################
# Create Rule
############################################

echo
echo "Creating EventBridge Rule..."

aws events put-rule \
--name "$RULE_NAME" \
--event-pattern file://configs/eventbridge-pattern.json \
--state ENABLED

############################################
# Add Lambda Target
############################################

echo
echo "Attaching Lambda Target..."

aws events put-targets \
--rule "$RULE_NAME" \
--targets "Id"="1","Arn"="$LAMBDA_FUNCTION_ARN"

############################################
# Allow EventBridge to Invoke Lambda
############################################

echo
echo "Granting Invoke Permission..."

if ! aws lambda get-policy \
--function-name "$LAMBDA_FUNCTION_NAME" \
>/dev/null 2>&1
then

aws lambda add-permission \
--function-name "$LAMBDA_FUNCTION_NAME" \
--statement-id AllowEventBridgeInvoke \
--action lambda:InvokeFunction \
--principal events.amazonaws.com \
--source-arn arn:aws:events:${AWS_REGION}:${AWS_ACCOUNT_ID}:rule/${RULE_NAME}

else

echo "Lambda policy already exists."

fi

############################################
# Verify Rule
############################################

echo
echo "========================================"
echo "EventBridge Rule"
echo "========================================"

aws events describe-rule \
--name "$RULE_NAME"

echo
echo "========================================"
echo "Targets"
echo "========================================"

aws events list-targets-by-rule \
--rule "$RULE_NAME"

############################################
# Save Resources
############################################

cat >> resource.env <<EOF

EVENTBRIDGE_RULE=$RULE_NAME

EOF

############################################

echo
echo "========================================"
echo "EventBridge Configuration Complete"
echo "========================================"