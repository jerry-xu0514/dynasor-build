#!/bin/bash
set -e

################################################################################
# Load environment variables from .env
################################################################################
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/.env"

# If IMAGE_TAG isn't set in .env, default to "latest"
: "${IMAGE_TAG:=latest}"
CONTAINER_NAME="trtllm_container"

################################################################################
# 1) Log in to ECR
################################################################################
echo "Authenticating to ECR..."
aws ecr get-login-password --region "$AWS_REGION" \
  | docker login --username AWS --password-stdin "$ECR_REPO_URI"

################################################################################
# 2) Pull the Docker image from ECR
################################################################################
echo "Pulling Docker image from ECR..."
docker pull "$ECR_REPO_URI:$IMAGE_TAG"

################################################################################
# 3) Run the container, overriding the entrypoint
#    so it doesn't auto-run the TRT-LLM dev build script.
################################################################################
echo "Running Docker container [$CONTAINER_NAME] in detached mode with a no-op command..."

# Remove old container if it exists
docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true

docker run -d \
  --name "$CONTAINER_NAME" \
  --gpus=all \
  --ipc=host \
  --ulimit memlock=-1 \
  --ulimit stack=67108864 \
  --entrypoint /bin/bash \
  "$ECR_REPO_URI:$IMAGE_TAG" \
  -c "sleep infinity"

echo "Container [$CONTAINER_NAME] started."
echo "Use 'docker logs -f $CONTAINER_NAME' or 'docker exec -it $CONTAINER_NAME bash' to interact with it."
