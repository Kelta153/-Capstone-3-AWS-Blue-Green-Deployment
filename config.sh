#!/bin/bash

########################################
# Project Configuration
########################################

export PROJECT="BlueGreenCapstone"

export REGION="us-east-1"

########################################
# Network
########################################

export VPC_CIDR="10.0.0.0/16"

export PUBLIC_SUBNET_A_CIDR="10.0.1.0/24"

export PUBLIC_SUBNET_B_CIDR="10.0.2.0/24"

export PRIVATE_SUBNET_A_CIDR="10.0.11.0/24"

export PRIVATE_SUBNET_B_CIDR="10.0.12.0/24"

########################################
# Availability Zones
########################################

export AZ1="us-east-1a"

export AZ2="us-east-1b"

########################################
# EC2
########################################

export INSTANCE_TYPE="t3.micro"

export KEY_NAME="BlueGreen-KeyPair"

########################################
# RDS
########################################

export DB_NAME="telecomdb"

export DB_ENGINE="mysql"

export DB_PORT="3306"

########################################
# Application
########################################

export BLUE_VERSION="1.0"

export GREEN_VERSION="2.0"