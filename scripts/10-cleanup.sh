#!/usr/bin/env bash

set -euo pipefail

############################################
# Blue-Green Deployment Capstone
# Script: 10-cleanup.sh
#
# Purpose:
# Destroy all AWS resources created
# during this project.
############################################

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

source resource.env

############################################

delete_if_exists () {

"$@" 2>/dev/null || true

}

############################################

echo
echo "======================================="
echo "Blue-Green Cleanup"
echo "======================================="
echo

############################################
# EventBridge
############################################

echo "Removing EventBridge..."

delete_if_exists aws events remove-targets \
--rule "$EVENTBRIDGE_RULE" \
--ids 1

delete_if_exists aws events delete-rule \
--name "$EVENTBRIDGE_RULE"

############################################
# CloudWatch
############################################

echo "Deleting Alarm..."

delete_if_exists aws cloudwatch delete-alarms \
--alarm-names "$CLOUDWATCH_ALARM"

############################################
# SNS
############################################

echo "Deleting SNS..."

SUBSCRIPTIONS=$(aws sns list-subscriptions-by-topic \
--topic-arn "$SNS_TOPIC_ARN" \
--query "Subscriptions[].SubscriptionArn" \
--output text 2>/dev/null || true)

for SUB in $SUBSCRIPTIONS
do
    delete_if_exists aws sns unsubscribe \
    --subscription-arn "$SUB"
done

delete_if_exists aws sns delete-topic \
--topic-arn "$SNS_TOPIC_ARN"

############################################
# Lambda
############################################

echo "Deleting Lambda..."

delete_if_exists aws lambda delete-function \
--function-name "$LAMBDA_FUNCTION_NAME"

############################################
# IAM Lambda
############################################

echo "Deleting Lambda IAM..."

delete_if_exists aws iam detach-role-policy \
--role-name "$LAMBDA_ROLE_NAME" \
--policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole

delete_if_exists aws iam detach-role-policy \
--role-name "$LAMBDA_ROLE_NAME" \
--policy-arn arn:aws:iam::$AWS_ACCOUNT_ID:policy/BlueGreenRollbackPolicy

delete_if_exists aws iam delete-role \
--role-name "$LAMBDA_ROLE_NAME"

############################################
# ALB
############################################

echo "Deleting Listener..."

delete_if_exists aws elbv2 delete-listener \
--listener-arn "$LISTENER_ARN"

echo "Deleting Load Balancer..."

delete_if_exists aws elbv2 delete-load-balancer \
--load-balancer-arn "$ALB_ARN"

echo "Waiting..."

sleep 30

############################################
# Target Groups
############################################

delete_if_exists aws elbv2 delete-target-group \
--target-group-arn "$BLUE_TG_ARN"

delete_if_exists aws elbv2 delete-target-group \
--target-group-arn "$GREEN_TG_ARN"

############################################
# EC2
############################################

echo "Terminating EC2..."

delete_if_exists aws ec2 terminate-instances \
--instance-ids \
"$BLUE_INSTANCE_ID" \
"$GREEN_INSTANCE_ID"

aws ec2 wait instance-terminated \
--instance-ids \
"$BLUE_INSTANCE_ID" \
"$GREEN_INSTANCE_ID" || true

############################################
# Key Pair
############################################

delete_if_exists aws ec2 delete-key-pair \
--key-name "$KEY_NAME"

rm -f "${KEY_NAME}.pem"

############################################
# Instance Profile
############################################

delete_if_exists aws iam remove-role-from-instance-profile \
--instance-profile-name BlueGreenEC2SSMProfile \
--role-name BlueGreenEC2SSMRole

delete_if_exists aws iam delete-instance-profile \
--instance-profile-name BlueGreenEC2SSMProfile

delete_if_exists aws iam detach-role-policy \
--role-name BlueGreenEC2SSMRole \
--policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore

delete_if_exists aws iam delete-role \
--role-name BlueGreenEC2SSMRole

############################################
# RDS
############################################

echo "Deleting RDS..."

delete_if_exists aws rds delete-db-instance \
--db-instance-identifier "$DB_IDENTIFIER" \
--skip-final-snapshot

aws rds wait db-instance-deleted \
--db-instance-identifier "$DB_IDENTIFIER" || true

delete_if_exists aws rds delete-db-subnet-group \
--db-subnet-group-name "$DB_SUBNET_GROUP"

############################################
# Security Groups
############################################

delete_if_exists aws ec2 delete-security-group \
--group-id "$RDS_SG"

delete_if_exists aws ec2 delete-security-group \
--group-id "$WEB_SG"

delete_if_exists aws ec2 delete-security-group \
--group-id "$ALB_SG"

############################################
# Route Tables
############################################

delete_if_exists aws ec2 disassociate-route-table \
--association-id "$PUBLIC_RT_ASSOC_A"

delete_if_exists aws ec2 disassociate-route-table \
--association-id "$PUBLIC_RT_ASSOC_B"

delete_if_exists aws ec2 disassociate-route-table \
--association-id "$PRIVATE_RT_ASSOC_A"

delete_if_exists aws ec2 disassociate-route-table \
--association-id "$PRIVATE_RT_ASSOC_B"

delete_if_exists aws ec2 delete-route-table \
--route-table-id "$PUBLIC_ROUTE_TABLE"

delete_if_exists aws ec2 delete-route-table \
--route-table-id "$PRIVATE_ROUTE_TABLE"

############################################
# Internet Gateway
############################################

delete_if_exists aws ec2 detach-internet-gateway \
--internet-gateway-id "$IGW_ID" \
--vpc-id "$VPC_ID"

delete_if_exists aws ec2 delete-internet-gateway \
--internet-gateway-id "$IGW_ID"

############################################
# Subnets
############################################

delete_if_exists aws ec2 delete-subnet \
--subnet-id "$PUBLIC_SUBNET_A"

delete_if_exists aws ec2 delete-subnet \
--subnet-id "$PUBLIC_SUBNET_B"

delete_if_exists aws ec2 delete-subnet \
--subnet-id "$PRIVATE_SUBNET_A"

delete_if_exists aws ec2 delete-subnet \
--subnet-id "$PRIVATE_SUBNET_B"

############################################
# VPC
############################################

delete_if_exists aws ec2 delete-vpc \
--vpc-id "$VPC_ID"

############################################

echo
echo "======================================="
echo "Cleanup Complete"
echo "======================================="

echo
echo "All project resources have been removed."