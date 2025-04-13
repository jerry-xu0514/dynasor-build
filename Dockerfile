# Use NVIDIA's PyTorch base image
FROM nvcr.io/nvidia/pytorch:24.02-py3

# Install necessary dependencies
RUN apt-get update && apt-get install -y \
    git git-lfs cmake build-essential \
    python3-dev python3-pip \
    && rm -rf /var/lib/apt/lists/*

# Install Git LFS
RUN git lfs install

# Set working directory
WORKDIR /workspace

# Clone TensorRT-LLM repository and its submodules
RUN git clone https://github.com/NVIDIA/TensorRT-LLM.git && \
    cd TensorRT-LLM && \
    git submodule update --init --recursive && \
    git lfs pull

# Set working directory to the cloned repository
WORKDIR /workspace/TensorRT-LLM

# Build the Python wheel for TensorRT-LLM
RUN python3 ./scripts/build_wheel.py --clean --trt_root /usr/local/tensorrt

# Install the built wheel
RUN pip install ./build/tensorrt_llm*.whl

# Set the default command
CMD ["/bin/bash"]