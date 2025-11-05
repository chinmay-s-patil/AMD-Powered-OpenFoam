#!/bin/bash
# File: AMDPoweredOpenFoam/fix_build_issues.sh
# Auto-fix all build issues

set -e

echo "Fixing simpleHIPFoam build issues..."

# 1. Fix Make/options - remove the problematic comment line
echo "  [1/5] Fixing Make/options..."
sed -i '37d' applications/solvers/simpleHIPFoam/Make/options

# 2. Fix hipSIMPLE.H - move rocblas_handle inside class
echo "  [2/5] Fixing hipSIMPLE.H..."
cat > applications/solvers/simpleHIPFoam/hipSolver/hipSIMPLE.H << 'EOF'
// hipSIMPLE.H
// HIP-accelerated linear solver interface for OpenFOAM

#ifndef hipSIMPLE_H
#define hipSIMPLE_H

#include "fvCFD.H"
#include <hip/hip_runtime.h>
#include <rocsparse/rocsparse.h>
#include <rocblas/rocblas.h>
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
    float *d_diag;
    
    rocsparse_handle handle_;
    rocsparse_mat_descr descr_;
    rocblas_handle blas_handle_;
    
    // Matrix dimensions
    label nCells_;
    label nnz_;
    
    // Conversion buffers
    std::vector<int> rowPtr_;
    std::vector<int> colInd_;
    std::vector<float> values_;
    std::vector<float> diag_;
    
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
    label PCG(float* x, const float* b, int maxIter, float tol);
    
    // Initialize HIP resources
    void initializeHIP();
    
    // Cleanup
    void cleanup();
};

#endif // hipSIMPLE_H
EOF

# 3. Fix simpleHIPFoam.C include path
echo "  [3/5] Fixing simpleHIPFoam.C..."
sed -i 's|#include "hipSIMPLE.H"|#include "hipSolver/hipSIMPLE.H"|' applications/solvers/simpleHIPFoam/simpleHIPFoam.C

# 4. Add missing newlines to all .H files
echo "  [4/5] Adding missing newlines..."
for file in applications/solvers/simpleHIPFoam/*.H; do
    if [ -f "$file" ]; then
        # Add newline if missing
        tail -c1 "$file" | read -r _ || echo "" >> "$file"
    fi
done

# 5. Clean old build artifacts
echo "  [5/5] Cleaning old build artifacts..."
cd applications/solvers/simpleHIPFoam
wclean 2>/dev/null || rm -rf Make/linux64*
cd ../../..

echo ""
echo "✓ All fixes applied!"
echo ""
echo "Now run: ./Allwmake"