#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# 1) LOAD ENV VARIABLES
###############################################################################
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/.env"

: "${TRT_LLM_DIR:="$HOME/TensorRT-LLM"}"
: "${BASE_TAG:="24.03-py3"}"            # Driver‑565‑compatible NGC tag
: "${PUBLIC_ECR_REPO_URI:="public.ecr.aws/v9v6m5w2/dynasor-trtllm"}"
: "${IMAGE_TAG:="${BASE_TAG}"}"
: "${LOCAL_FINAL_IMAGE_NAME:="tensorrt_llm_local:${IMAGE_TAG}"}"

###############################################################################
# 2) ENSURE TENSORRT‑LLM SOURCE IS PRESENT
###############################################################################
if [[ ! -d "${TRT_LLM_DIR}/.git" ]]; then
  echo ">>> Cloning TensorRT‑LLM into ${TRT_LLM_DIR}"
  sudo apt-get update && sudo apt-get install -y git git-lfs
  git lfs install
  git clone https://github.com/NVIDIA/TensorRT-LLM.git "${TRT_LLM_DIR}"
fi

cd "${TRT_LLM_DIR}"
git pull --ff-only
git submodule update --init --recursive

echo ">>> Source at commit $(git rev-parse --short HEAD)"

###############################################################################
# 3) BUILD THE DEV IMAGE ON DRIVER‑COMPATIBLE BASE
###############################################################################
# Makefile key is TAG=<NGC tag>

echo ">>> Building dev image tensorrt_llm/devel:${BASE_TAG} (CUDA_ARCHS=${CUDA_ARCHS:-all})"
make -C docker build TAG="${BASE_TAG}" CUDA_ARCHS="${CUDA_ARCHS:-all}"

DEV_IMAGE="tensorrt_llm/devel:${BASE_TAG}"

###############################################################################
# 4) BUILD + INSTALL THE WHEEL INSIDE THE DEV IMAGE
###############################################################################
CONTAINER_NAME="trt_llm_build_container"
docker rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true

docker run -d \
  --name "${CONTAINER_NAME}" \
  --gpus all \
  --ipc host \
  --ulimit memlock=-1 --ulimit stack=67108864 \
  -v "${TRT_LLM_DIR}:/code/tensorrt_llm" \
  -w /code/tensorrt_llm \
  "${DEV_IMAGE}" \
  bash -c "set -e; \
           python3 scripts/build_wheel.py --clean --python_bindings --benchmarks \
                 --cuda_architectures '${CUDA_ARCHS:-all}'; \
           pip install ./build/tensorrt_llm*.whl"

echo ">>> Waiting for wheel build to finish…"
docker wait "${CONTAINER_NAME}"

###############################################################################
# 5) COMMIT THE FILLED ENVIRONMENT TO A RUNTIME IMAGE
###############################################################################

docker commit "${CONTAINER_NAME}" "${LOCAL_FINAL_IMAGE_NAME}"
docker rm "${CONTAINER_NAME}"

echo ">>> Created snapshot ${LOCAL_FINAL_IMAGE_NAME} (driver ≤565 compatible)"

###############################################################################
# 6) PUSH TO PUBLIC ECR (token lasts 12h but public repo requires only login)
###############################################################################
aws ecr-public get-login-password --region us-east-1 | \
  docker login -u AWS --password-stdin public.ecr.aws

docker tag "${LOCAL_FINAL_IMAGE_NAME}" "${PUBLIC_ECR_REPO_URI}:${IMAGE_TAG}"
echo ">>> Pushing to ${PUBLIC_ECR_REPO_URI}:${IMAGE_TAG}"
docker push "${PUBLIC_ECR_REPO_URI}:${IMAGE_TAG}"

echo "\n>>> Success! Image ready to pull on RunPod. Use driver ≥ 560 (RunPod 565 qualifies)."
