// matmul_hip.cpp
// Compile: hipcc -O3 -std=c++17 matmul_hip.cpp -o matmul_hip
#include <hip/hip_runtime.h>
#include <cstdio>
#include <cstdlib>
#include <chrono>
#include <cmath>
#include <iostream>

#define TILE 16

__global__ void matMulTiled(const float* A, const float* B, float* C, int N) {
    __shared__ float sA[TILE][TILE];
    __shared__ float sB[TILE][TILE];

    int row = blockIdx.y * TILE + threadIdx.y;
    int col = blockIdx.x * TILE + threadIdx.x;
    float acc = 0.0f;

    int numPhases = (N + TILE - 1) / TILE;
    for (int p = 0; p < numPhases; ++p) {
        int aCol = p * TILE + threadIdx.x;
        int bRow = p * TILE + threadIdx.y;

        sA[threadIdx.y][threadIdx.x] = (row < N && aCol < N) ? A[row * N + aCol] : 0.0f;
        sB[threadIdx.y][threadIdx.x] = (bRow < N && col < N) ? B[bRow * N + col] : 0.0f;

        __syncthreads();

        for (int k = 0; k < TILE; ++k) {
            acc += sA[threadIdx.y][k] * sB[k][threadIdx.x];
        }
        __syncthreads();
    }

    if (row < N && col < N) {
        C[row * N + col] = acc;
    }
}

void cpuMatMul(const float* A, const float* B, float* C, int N) {
    for (int i = 0; i < N; ++i) {
        for (int j = 0; j < N; ++j) {
            float s = 0.0f;
            for (int k = 0; k < N; ++k) s += A[i*N + k] * B[k*N + j];
            C[i*N + j] = s;
        }
    }
}

int main(int argc, char** argv) {
    int N = 1024;
    if (argc > 1) N = std::atoi(argv[1]);

    size_t bytes = (size_t)N * N * sizeof(float);
    float *hA = (float*)malloc(bytes), *hB = (float*)malloc(bytes), *hC = (float*)malloc(bytes);
    float *hC_ref = (float*)malloc(bytes);

    // Initialize
    for (size_t i = 0; i < (size_t)N * N; ++i) {
        hA[i] = static_cast<float>( (i % 17) * 0.03125f ); // reproducible-ish
        hB[i] = static_cast<float>( (i % 13) * 0.0625f );
    }

    // Device buffers
    float *dA, *dB, *dC;
    hipMalloc(&dA, bytes);
    hipMalloc(&dB, bytes);
    hipMalloc(&dC, bytes);

    hipMemcpy(dA, hA, bytes, hipMemcpyHostToDevice);
    hipMemcpy(dB, hB, bytes, hipMemcpyHostToDevice);

    dim3 block(TILE, TILE);
    dim3 grid( (N + TILE - 1) / TILE, (N + TILE - 1) / TILE );

    // GPU timing with hip events
    hipEvent_t start, stop;
    hipEventCreate(&start);
    hipEventCreate(&stop);
    hipEventRecord(start, 0);

    hipLaunchKernelGGL(matMulTiled, grid, block, 0, 0, dA, dB, dC, N);

    hipEventRecord(stop, 0);
    hipEventSynchronize(stop);

    float ms = 0.0f;
    hipEventElapsedTime(&ms, start, stop);

    hipMemcpy(hC, dC, bytes, hipMemcpyDeviceToHost);

    // CPU reference (time it)
    auto t0 = std::chrono::high_resolution_clock::now();
    cpuMatMul(hA, hB, hC_ref, N);
    auto t1 = std::chrono::high_resolution_clock::now();
    double cpu_ms = std::chrono::duration<double, std::milli>(t1 - t0).count();

    // Verify
    double max_err = 0.0;
    for (size_t i = 0; i < (size_t)N * N; ++i) {
        max_err = std::fmax(max_err, std::fabs(static_cast<double>(hC_ref[i]) - hC[i]));
    }

    std::printf("N=%d | GPU kernel time: %.3f ms | CPU time: %.3f ms | max error: %.6e\n",
                N, ms, cpu_ms, max_err);

    // Cleanup
    hipFree(dA);
    hipFree(dB);
    hipFree(dC);
    free(hA); free(hB); free(hC); free(hC_ref);

    hipEventDestroy(start);
    hipEventDestroy(stop);

    return (max_err < 1e-2) ? 0 : 1;
}
