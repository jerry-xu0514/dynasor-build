#!/bin/bash
set -e

# ------------------------------------------------------------------------------
# 1) Load environment variables from .env
# ------------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/.env"

# If IMAGE_TAG isn't set in .env, default to "latest"
: "${IMAGE_TAG:=latest}"

# ------------------------------------------------------------------------------
# 2) Log in to ECR
# ------------------------------------------------------------------------------
echo "Authenticating to ECR..."
aws ecr get-login-password --region "$AWS_REGION" \
  | docker login --username AWS --password-stdin "$ECR_REPO_URI"

# ------------------------------------------------------------------------------
# 3) Pull the Docker image from ECR
# ------------------------------------------------------------------------------
echo "Pulling Docker image from ECR..."
docker pull "$ECR_REPO_URI:$IMAGE_TAG"

# ------------------------------------------------------------------------------
# 4) (Optional) Run the container
# ------------------------------------------------------------------------------
CONTAINER_NAME="trtllm_container"

# If you want to remove any existing container with that name, uncomment:
# docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true

echo "Running Docker container [$CONTAINER_NAME] in detached mode..."
docker run -d \
  --name "$CONTAINER_NAME" \
  --gpus=all \
  --ipc=host \
  --ulimit memlock=-1 \
  --ulimit stack=67108864 \
  "$ECR_REPO_URI:$IMAGE_TAG"

echo "Container [$CONTAINER_NAME] started."
echo "Use 'docker logs -f $CONTAINER_NAME' or 'docker exec -it $CONTAINER_NAME bash' to interact with it."
