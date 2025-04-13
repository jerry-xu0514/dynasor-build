#!/bin/bash
set -e

# Environment variables; update as needed
source "$(dirname "$0")/.env"

: "${IMAGE_TAG:=latest}"
# Authenticate to ECR
echo "Authenticating to ECR..."
aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$ECR_REPO_URI"

# Pull the Docker image
echo "Pulling Docker image from ECR..."
docker pull "$ECR_REPO_URI:$IMAGE_TAG"

# Optionally, run the container (adjust run parameters as needed)
echo "Running Docker container..."
docker run -d --name trtllm_container --gpus all "$ECR_REPO_URI:$IMAGE_TAG"

echo "Image pulled and container started."