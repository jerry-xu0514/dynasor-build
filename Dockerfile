FROM nvcr.io/nvidia/pytorch:24.02-py3

# Base dependencies
RUN apt-get update && apt-get install -y \
    git git-lfs cmake build-essential \
    python3-dev python3-pip \
    && rm -rf /var/lib/apt/lists/*

# Set working dir
WORKDIR /workspace

# Clone TRT-LLM with LFS + submodules
RUN git lfs install && \
    git clone https://github.com/NVIDIA/TensorRT-LLM.git && \
    cd TensorRT-LLM && \
    git submodule update --init --recursive && \
    git lfs pull

# Set TRT-LLM as working dir for build
WORKDIR /workspace/TensorRT-LLM

# Install Python dependencies (if needed)
COPY requirements.txt ./requirements.txt
RUN pip install --upgrade pip && pip install -r requirements.txt || true

# Build the wheel
RUN python3 ./scripts/build_wheel.py --clean --trt_root /usr/local/tensorrt

# Install the wheel into the image
RUN pip install dist/*.whl

# Set default shell (optional)
CMD ["/bin/bash"]