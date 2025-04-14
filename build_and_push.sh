#!/usr/bin/env bash
set -e

###############################################################################
# 1) LOAD ENV VARIABLES
###############################################################################
# We'll assume `.env` is in the same directory as this script:
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/.env"

# Now we have variables like:
#   $AWS_ACCESS_KEY_ID
#   $AWS_SECRET_ACCESS_KEY
#   $AWS_REGION
#   $ECR_REPO_URI
#   $IMAGE_TAG
#   $TRT_LLM_DIR
#   $CUDA_ARCHS
#   $LOCAL_FINAL_IMAGE_NAME
#
# Make sure all are set; if not, set defaults or throw an error as needed.

: "${TRT_LLM_DIR:="$HOME/TensorRT-LLM"}"
: "${LOCAL_FINAL_IMAGE_NAME:="tensorrt_llm_local:latest"}"

###############################################################################
# 2) CONFIGURE AWS CLI
###############################################################################
# We'll configure AWS CLI with the .env-provided credentials
echo ">>> Configuring AWS CLI with provided credentials"
aws configure set aws_access_key_id "$AWS_ACCESS_KEY_ID"
aws configure set aws_secret_access_key "$AWS_SECRET_ACCESS_KEY"
aws configure set default.region "$AWS_REGION"

###############################################################################
# 3) CLONE TENSORRT-LLM (IF NEEDED)
###############################################################################
if [ ! -d "$TRT_LLM_DIR" ]; then
  echo ">>> Cloning TensorRT-LLM into $TRT_LLM_DIR"
  sudo apt-get update && sudo apt-get install -y git git-lfs
  git lfs install
  git clone https://github.com/NVIDIA/TensorRT-LLM.git "$TRT_LLM_DIR"
  cd "$TRT_LLM_DIR"
  git submodule update --init --recursive
  git lfs pull
else
  echo ">>> Using existing TensorRT-LLM directory: $TRT_LLM_DIR"
  cd "$TRT_LLM_DIR"
fi

###############################################################################
# 4) BUILD THE OFFICIAL DEV DOCKER IMAGE USING NVIDIAS MAKEFILE
###############################################################################
echo ">>> Building dev Docker image: tensorrt_llm/devel:latest"
# The 'CUDA_ARCHS' argument restricts the GPU architectures compiled for.
make -C docker build CUDA_ARCHS="$CUDA_ARCHS"

###############################################################################
# 5) RUN A CONTAINER TO BUILD & INSTALL THE TRT-LLM WHEEL
###############################################################################
# We'll do it non-interactively, so no shell needed. We'll name the container:
CONTAINER_NAME="trt_llm_build_container"

# If a container with that name exists, remove it
docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true

echo ">>> Spinning up container [$CONTAINER_NAME] to build the TRT-LLM wheel..."

docker run -d \
  --name "$CONTAINER_NAME" \
  --gpus=all \
  --ipc=host \
  --ulimit memlock=-1 \
  --ulimit stack=67108864 \
  --volume "${TRT_LLM_DIR}:/code/tensorrt_llm" \
  --workdir /code/tensorrt_llm \
  tensorrt_llm/devel:latest \
  bash -c "
    set -e
    echo '>>> Building the wheel inside the container...'
    python3 scripts/build_wheel.py --clean --python_bindings --benchmarks --cuda_architectures '$CUDA_ARCHS'
    echo '>>> Installing the wheel...'
    pip install ./build/tensorrt_llm*.whl
    echo '>>> Done building & installing TensorRT-LLM.'
    exit 0
  "

echo ">>> Waiting for container [$CONTAINER_NAME] to finish building..."
docker wait "$CONTAINER_NAME"

###############################################################################
# 6) COMMIT THAT CONTAINER TO A NEW LOCAL IMAGE
###############################################################################
echo ">>> Committing container [$CONTAINER_NAME] to local image [$LOCAL_FINAL_IMAGE_NAME]"
docker commit "$CONTAINER_NAME" "$LOCAL_FINAL_IMAGE_NAME"

# Remove the build container (we no longer need it)
docker rm "$CONTAINER_NAME"

###############################################################################
# 7) PUSH THE NEW LOCAL IMAGE TO ECR
###############################################################################
echo ">>> Tagging and pushing to ECR: $ECR_REPO_URI:$IMAGE_TAG"

# Ensure we are logged in to ECR:
aws ecr get-login-password --region "$AWS_REGION" \
  | docker login --username AWS --password-stdin "$ECR_REPO_URI"

docker tag "$LOCAL_FINAL_IMAGE_NAME" "$ECR_REPO_URI:$IMAGE_TAG"
docker push "$ECR_REPO_URI:$IMAGE_TAG"

echo ">>> Success! Your final Docker image is pushed to $ECR_REPO_URI:$IMAGE_TAG"
echo ">>> Locally, it's also available as $LOCAL_FINAL_IMAGE_NAME"
