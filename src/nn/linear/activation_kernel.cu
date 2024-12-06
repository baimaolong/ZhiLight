#include "nn/linear/activation_kernel.h"
#include "nn/functions/activation.cuh"
#include "nn/functions/functions.h"
#include <bmengine/functions/element.h>
#include <bmengine/logger/std_log_op.hpp>
#include <bmengine/core/core.h>
#include <cuda_fp16.h>
#include <cuda_runtime_api.h>
#include "utils/exception.h"

namespace nn {

template<typename T>
static __global__ void BM_KERNEL(gelu_inplace)(
    size_t n,
    T *inp // (n)
) {
    size_t i = (size_t) blockIdx.x * blockDim.x + threadIdx.x;
    if (i < n) {
        inp[i] = gelu(float(inp[i]));
    }
}

template<typename T>
static __global__ void BM_KERNEL(silu_inplace)(
    size_t n,
    T *inp // (n)
) {
    size_t i = (size_t) blockIdx.x * blockDim.x + threadIdx.x;
    if (i < n) {
        inp[i] = silu(float(inp[i]));
    }
}

void gelu_inplace(const core::Tensor& inp, cudaStream_t stream) {
    size_t n = inp.numel();
    int threads = min(round_up(n, 32), (size_t) 1024);
    dim3 gridDim(round_up(n, threads) / threads, 1, 1);
    dim3 blockDim(threads, 1, 1);

    BM_DTYPE_DISPATCH_FLOAT(inp.dtype(), {
        BM_KERNEL(gelu_inplace) < scalar_t >
        <<<gridDim, blockDim, 0, stream>>>(n, inp.data<scalar_t>());
    });
}

void silu_inplace(const core::Tensor& inp, cudaStream_t stream) {
    size_t n = inp.numel();
    int threads = min(round_up(n, 32), (size_t) 1024);
    dim3 gridDim(round_up(n, threads) / threads, 1, 1);
    dim3 blockDim(threads, 1, 1);

    BM_DTYPE_DISPATCH_FLOAT(inp.dtype(), {
        BM_KERNEL(silu_inplace) < scalar_t >
        <<<gridDim, blockDim, 0, stream>>>(n, inp.data<scalar_t>());
    });
}

template<typename T>
static __global__ void KERNEL_gelu_mul_inplace(
    size_t n,
    T *inp, // (n)
    const T *in2 // (n)
) {
    size_t i = (size_t) blockIdx.x * blockDim.x + threadIdx.x;
    if (i < n) {
        inp[i] = gelu(float(inp[i])) * float(in2[i]);
    }
}
template<typename T>
static __global__ void KERNEL_silu_mul_inplace(
    size_t n,
    T *inp, // (n)
    const T *in2 // (n)
) {
    size_t i = (size_t) blockIdx.x * blockDim.x + threadIdx.x;
    if (i < n) {
        inp[i] = silu(float(inp[i])) * float(in2[i]);
    }
}

void gate_mul_inplace(
    const core::Context& ctx,
    core::Tensor& inp,
    const core::Tensor& in2,
    const std::string& gate_type) {
    auto stream = ctx.current_stream()->ptr;
    size_t n = inp.numel();
    int threads = round_up_thread(n);
    dim3 gridDim(round_up(n, threads) / threads);
    dim3 blockDim(threads);

    if (gate_type == "silu") {
        BM_DTYPE_DISPATCH_FLOAT(inp.dtype(), {
            KERNEL_silu_mul_inplace< scalar_t >
            <<<gridDim, blockDim, 0, stream>>>(n, inp.data<scalar_t>(), in2.data<scalar_t>());
        });
    } else if (gate_type == "gelu") {
        BM_DTYPE_DISPATCH_FLOAT(inp.dtype(), {
            KERNEL_gelu_mul_inplace< scalar_t >
            <<<gridDim, blockDim, 0, stream>>>(n, inp.data<scalar_t>(), in2.data<scalar_t>());
        });
    } else {
        throw std::runtime_error("Unsupported gate type: " + gate_type);
    }
}

}