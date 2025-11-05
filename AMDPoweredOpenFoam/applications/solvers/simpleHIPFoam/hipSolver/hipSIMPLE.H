// hipSIMPLE.H
// HIP-accelerated linear solver interface for OpenFOAM

#ifndef hipSIMPLE_H
#define hipSIMPLE_H

#include "fvCFD.H"
#include <hip/hip_runtime.h>
#include <rocsparse/rocsparse.h>
#include <vector>

class hipSIMPLE
{
private:
    const fvMesh& mesh_;
    volScalarField& p_;
    volVectorField& U_;
    surfaceScalarField& phi_;
    
    // HIP device data
    float *d_x, *d_b, *d_r;
    int *d_rowPtr, *d_colInd;
    float *d_values;
    
    rocsparse_handle handle_;
    rocsparse_mat_descr descr_;
    
    // Matrix dimensions
    label nCells_;
    label nnz_;
    
    // Conversion buffers
    std::vector<int> rowPtr_;
    std::vector<int> colInd_;
    std::vector<float> values_;
    
    bool initialized_;

public:
    hipSIMPLE(const fvMesh& mesh, volScalarField& p, 
              volVectorField& U, surfaceScalarField& phi);
    
    ~hipSIMPLE();
    
    // Convert OpenFOAM lduMatrix to CSR format
    void convertToCSR(const lduMatrix& matrix);
    
    // Solve using HIP-accelerated iterative solver
    void solveHIP(volScalarField& psi, const volScalarField& source,
                  const dictionary& solverControls);
    
    // PCG solver on GPU
    void PCG(float* x, const float* b, int maxIter, float tol);
    
    // Initialize HIP resources
    void initializeHIP();
    
    // Cleanup
    void cleanup();
};

#endif // hipSIMPLE_H