#!/bin/bash
set -e

# Environment variables; update as needed
ECR_REPO_URI="${ECR_REPO_URI:-123456789012.dkr.ecr.us-west-2.amazonaws.com/trtllm-dev}"
IMAGE_TAG="${IMAGE_TAG:-dev-latest}"
AWS_REGION="${AWS_REGION:-us-west-2}"

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