#!/usr/bin/env bash

set -euo pipefail

############################################
# Blue-Green Deployment Capstone
# Script: 09-lambda.sh
#
# Purpose:
#   • Package Lambda
#   • Create IAM Role
#   • Attach Policies
#   • Deploy Lambda
############################################

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

source resource.env

############################################
# Validate
############################################

: "${LISTENER_ARN:?Missing LISTENER_ARN}"
: "${BLUE_TG_ARN:?Missing BLUE_TG_ARN}"
: "${GREEN_TG_ARN:?Missing GREEN_TG_ARN}"

AWS_REGION=$(aws configure get region)

AWS_ACCOUNT_ID=$(aws sts get-caller-identity \
--query Account \
--output text)

ROLE_NAME="BlueGreenRollbackLambdaRole"

FUNCTION_NAME="BlueGreenRollback"

############################################
# Package Lambda
############################################

echo
echo "Packaging Lambda..."

mkdir -p build

rm -f build/rollback.zip

if command -v zip >/dev/null 2>&1
then

(
cd lambda
zip -q ../build/rollback.zip rollback.py
)

else

powershell -Command \
"Compress-Archive -Path lambda\rollback.py -DestinationPath build\rollback.zip -Force"

fi

############################################
# IAM Role
############################################

echo
echo "Creating IAM Role..."

if ! aws iam get-role \
--role-name "$ROLE_NAME" >/dev/null 2>&1
then

aws iam create-role \
--role-name "$ROLE_NAME" \
--assume-role-policy-document file://policies/lambda-trust-policy.json

aws iam attach-role-policy \
--role-name "$ROLE_NAME" \
--policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole

aws iam attach-role-policy \
--role-name "$ROLE_NAME" \
--policy-arn arn:aws:iam::$AWS_ACCOUNT_ID:policy/BlueGreenRollbackPolicy

echo "Waiting for IAM propagation..."

sleep 15

fi

############################################
# Create or Update Lambda
############################################

echo
echo "Deploying Lambda..."

if aws lambda get-function \
--function-name "$FUNCTION_NAME" >/dev/null 2>&1
then

aws lambda update-function-code \
--function-name "$FUNCTION_NAME" \
--zip-file fileb://build/rollback.zip

aws lambda update-function-configuration \
--function-name "$FUNCTION_NAME" \
--runtime python3.13 \
--handler rollback.lambda_handler \
--timeout 30 \
--environment "Variables={
LISTENER_ARN=$LISTENER_ARN,
BLUE_TARGET_GROUP_ARN=$BLUE_TG_ARN,
GREEN_TARGET_GROUP_ARN=$GREEN_TG_ARN
}"

else

aws lambda create-function \
--function-name "$FUNCTION_NAME" \
--runtime python3.13 \
--handler rollback.lambda_handler \
--role arn:aws:iam::$AWS_ACCOUNT_ID:role/$ROLE_NAME \
--zip-file fileb://build/rollback.zip \
--timeout 30 \
--environment "Variables={
LISTENER_ARN=$LISTENER_ARN,
BLUE_TARGET_GROUP_ARN=$BLUE_TG_ARN,
GREEN_TARGET_GROUP_ARN=$GREEN_TG_ARN
}"

fi

############################################
# Wait
############################################

echo
echo "Waiting for Lambda..."

aws lambda wait function-active-v2 \
--function-name "$FUNCTION_NAME"

############################################
# Retrieve ARN
############################################

LAMBDA_FUNCTION_ARN=$(aws lambda get-function \
--function-name "$FUNCTION_NAME" \
--query "Configuration.FunctionArn" \
--output text)

############################################
# Save
############################################

cat >> resource.env <<EOF

AWS_REGION=$AWS_REGION
AWS_ACCOUNT_ID=$AWS_ACCOUNT_ID

LAMBDA_FUNCTION_NAME=$FUNCTION_NAME
LAMBDA_FUNCTION_ARN=$LAMBDA_FUNCTION_ARN

LAMBDA_ROLE_NAME=$ROLE_NAME

EOF

############################################
# Verification
############################################

echo
echo "========================================"

echo "Lambda Function"

echo "========================================"

aws lambda get-function \
--function-name "$FUNCTION_NAME" \
--query "Configuration.[FunctionName,Runtime,State]" \
--output table

echo
echo "Lambda ARN"

echo "$LAMBDA_FUNCTION_ARN"

echo
echo "Deployment Complete"