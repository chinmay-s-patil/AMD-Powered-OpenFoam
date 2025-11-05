#include "hipSolver.h"
#include <hip/hip_runtime.h>
#include <iostream>

__global__ void addOneKernel(float* field, int N) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if(i < N) field[i] += 1.0f;
}

void hipSolver(ScalarField &field, int nSteps) {
    float *dField;
    size_t bytes = field.N * sizeof(float);

    hipMalloc(&dField, bytes);
    hipMemcpy(dField, field.data, bytes, hipMemcpyHostToDevice);

    int blockSize = 256;
    int numBlocks = (field.N + blockSize - 1) / blockSize;

    for(int t=0; t<nSteps; t++)
        hipLaunchKernelGGL(addOneKernel, dim3(numBlocks), dim3(blockSize), 0, 0, dField, field.N);

    hipMemcpy(field.data, dField, bytes, hipMemcpyDeviceToHost);
    hipFree(dField);

    std::cout << "HIP solver finished\n";
}
