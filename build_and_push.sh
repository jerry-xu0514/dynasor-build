#!/bin/bash
set -e

# Source environment variables from the .env file
source "$(dirname "$0")/.env"

# Configure AWS CLI using credentials from the .env file
aws configure set aws_access_key_id "$AWS_ACCESS_KEY_ID"
aws configure set aws_secret_access_key "$AWS_SECRET_ACCESS_KEY"
aws configure set default.region "$AWS_REGION"

: "${IMAGE_TAG:=latest}"

# Authenticate to ECR
echo "Authenticating to ECR..."
aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$ECR_REPO_URI"

# Build the Docker image (ensure your Dockerfile builds the wheel as needed)
echo "Building Docker image..."
docker build -t "$ECR_REPO_URI:$IMAGE_TAG" .

# Push the image to ECR
echo "Pushing Docker image to ECR..."
docker push "$ECR_REPO_URI:$IMAGE_TAG"

echo "Build and push complete."