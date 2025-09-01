#!/bin/bash

# Pull Prometheus image from Docker Hub
# echo "Pulling Prometheus image from Docker Hub"
# docker pull prom/prometheus:latest

echo "Initializing Terraform"
terraform init -var-file="deploy.tfvars"

echo "Running terraform plan"
terraform plan -var-file="deploy.tfvars" -out="plan.json"

echo "Applying Terraform configuration"
terraform apply --auto-approve -var-file="deploy.tfvars"