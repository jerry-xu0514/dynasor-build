#!/bin/bash
set -e

# Environment variables; update as needed
ECR_REPO_URI="${ECR_REPO_URI:-123456789012.dkr.ecr.us-west-2.amazonaws.com/trtllm-dev}"
IMAGE_TAG="${IMAGE_TAG:-dev-latest}"
AWS_REGION="${AWS_REGION:-us-west-2}"

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