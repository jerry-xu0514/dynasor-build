# *****************************************************************************
# Multi-stage Dockerfile for building a TensorRT-LLM wheel targeting Ampere GPUs
# *****************************************************************************

# -----------------------------------------------------------------------------
# Stage 0: Base image
# -----------------------------------------------------------------------------
ARG BASE_IMAGE=nvcr.io/nvidia/pytorch
ARG BASE_TAG=25.01-py3
ARG DEVEL_IMAGE=devel  # We'll refer to "devel" stage as our dev environment.

FROM ${BASE_IMAGE}:${BASE_TAG} AS base

# The default NGC PyTorch images have a pip constraint file; we remove it here.
RUN [ -f /etc/pip/constraint.txt ] && : > /etc/pip/constraint.txt || true

# Set up environment for Bash
ENV BASH_ENV=${BASH_ENV:-/etc/bash.bashrc}
ENV ENV=${ENV:-/etc/shinit_v2}
ARG GITHUB_MIRROR=""
ENV GITHUB_MIRROR=$GITHUB_MIRROR

SHELL ["/bin/bash", "-c"]

# -----------------------------------------------------------------------------
# Stage 1: Development environment
# -----------------------------------------------------------------------------
FROM base AS devel

# Change to the Python version you need
ARG PYTHON_VERSION="3.12.3"
RUN echo "Using Python version: $PYTHON_VERSION"

# Copy and run the installation scripts (these come from TensorRT-LLM/docker/common)
COPY docker/common/install_base.sh install_base.sh
RUN bash ./install_base.sh $PYTHON_VERSION && rm install_base.sh

COPY docker/common/install_cmake.sh install_cmake.sh
RUN bash ./install_cmake.sh && rm install_cmake.sh

COPY docker/common/install_ccache.sh install_ccache.sh
RUN bash ./install_ccache.sh && rm install_ccache.sh

COPY docker/common/install_cuda_toolkit.sh install_cuda_toolkit.sh
RUN bash ./install_cuda_toolkit.sh && rm install_cuda_toolkit.sh

# Download & install latest TensorRT release
ARG TRT_VER
ARG CUDA_VER
ARG CUDNN_VER
ARG NCCL_VER
ARG CUBLAS_VER
COPY docker/common/install_tensorrt.sh install_tensorrt.sh
RUN bash ./install_tensorrt.sh \
    --TRT_VER=${TRT_VER} \
    --CUDA_VER=${CUDA_VER} \
    --CUDNN_VER=${CUDNN_VER} \
    --NCCL_VER=${NCCL_VER} \
    --CUBLAS_VER=${CUBLAS_VER} && \
    rm install_tensorrt.sh

# Install latest Polygraphy
COPY docker/common/install_polygraphy.sh install_polygraphy.sh
RUN bash ./install_polygraphy.sh && rm install_polygraphy.sh

# Install mpi4py
COPY docker/common/install_mpi4py.sh install_mpi4py.sh
RUN bash ./install_mpi4py.sh && rm install_mpi4py.sh

# Install PyTorch if needed (skip = uses base image version)
ARG TORCH_INSTALL_TYPE="skip"
COPY docker/common/install_pytorch.sh install_pytorch.sh
RUN bash ./install_pytorch.sh $TORCH_INSTALL_TYPE && rm install_pytorch.sh

# Optionally reinstall OpenCV (headless)
RUN pip3 uninstall -y opencv && rm -rf /usr/local/lib/python3*/dist-packages/cv2/
RUN pip3 install opencv-python-headless --force-reinstall --no-deps

# -----------------------------------------------------------------------------
# Stage 2: Build the TensorRT-LLM wheel
# -----------------------------------------------------------------------------
FROM ${DEVEL_IMAGE} AS wheel

WORKDIR /src/tensorrt_llm

# Copy the source code into this stage
COPY benchmarks benchmarks
COPY cpp cpp
COPY scripts scripts
COPY tensorrt_llm tensorrt_llm
COPY 3rdparty 3rdparty
COPY .gitmodules setup.py requirements.txt requirements-dev.txt ./

# By default, we build a clean wheel with benchmarks & Python bindings,
# targeting both A100 (80) and A10/A40 (86).
ARG BUILD_WHEEL_ARGS="--clean --python_bindings --benchmarks --cuda_architectures \"80-real;86-real\""

# Create cache directories for pip and ccache to speed up rebuilds
RUN mkdir -p /root/.cache/pip /root/.cache/ccache
ENV CCACHE_DIR=/root/.cache/ccache

# Build the TensorRT-LLM wheel
RUN --mount=type=cache,target=/root/.cache/pip \
    --mount=type=cache,target=/root/.cache/ccache \
    python3 scripts/build_wheel.py ${BUILD_WHEEL_ARGS}

# -----------------------------------------------------------------------------
# Stage 3: Final release image
# -----------------------------------------------------------------------------
FROM ${DEVEL_IMAGE} AS release

WORKDIR /app/tensorrt_llm

# Create pip cache
RUN mkdir -p /root/.cache/pip

# Copy the built wheel from the "wheel" stage
COPY --from=wheel /src/tensorrt_llm/build/tensorrt_llm*.whl .

# Install the wheel
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install tensorrt_llm*.whl && \
    rm tensorrt_llm*.whl

# Copy docs, README, headers, etc. (optional but convenient)
COPY README.md ./
COPY docs docs
COPY cpp/include include

# Symlink the installed bins/libs from site-packages
RUN ln -sv $(python3 -c 'import site; print(f"{site.getsitepackages()[0]}/tensorrt_llm/bin")') bin && \
    test -f bin/executorWorker && \
    ln -sv $(python3 -c 'import site; print(f"{site.getsitepackages()[0]}/tensorrt_llm/libs")') lib && \
    test -f lib/libnvinfer_plugin_tensorrt_llm.so && \
    echo "/app/tensorrt_llm/lib" > /etc/ld.so.conf.d/tensorrt_llm.conf && \
    ldconfig

# Quick test that the newly installed library is found
RUN ! ( ldd -v bin/executorWorker | grep tensorrt_llm | grep -q "not found" )

# Optionally copy benchmarks / examples
ARG SRC_DIR=/src/tensorrt_llm
COPY --from=wheel ${SRC_DIR}/benchmarks benchmarks
ARG CPP_BUILD_DIR=${SRC_DIR}/cpp/build
COPY --from=wheel \
    ${CPP_BUILD_DIR}/benchmarks/bertBenchmark \
    ${CPP_BUILD_DIR}/benchmarks/gptManagerBenchmark \
    ${CPP_BUILD_DIR}/benchmarks/gptSessionBenchmark \
    ${CPP_BUILD_DIR}/benchmarks/disaggServerBenchmark \
    benchmarks/cpp/
COPY examples examples
RUN chmod -R a+w examples && \
    rm -v \
    benchmarks/cpp/bertBenchmark.cpp \
    benchmarks/cpp/gptManagerBenchmark.cpp \
    benchmarks/cpp/gptSessionBenchmark.cpp \
    benchmarks/cpp/disaggServerBenchmark.cpp \
    benchmarks/cpp/CMakeLists.txt

# Set environment variables with version info (optional)
ARG GIT_COMMIT
ARG TRT_LLM_VER
ENV TRT_LLM_GIT_COMMIT=${GIT_COMMIT} \
    TRT_LLM_VERSION=${TRT_LLM_VER}

# The final image is now ready to run with TensorRT-LLM installed.
# -----------------------------------------------------------------------------
