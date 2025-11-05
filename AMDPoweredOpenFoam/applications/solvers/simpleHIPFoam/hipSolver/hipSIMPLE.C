// hipSIMPLE.C
// Implementation of HIP-accelerated SIMPLE solver with rocBLAS

#include "hipSolver/hipSIMPLE.H"
#include <rocblas/rocblas.h>

hipSIMPLE::hipSIMPLE
(
    const fvMesh& mesh,
    volScalarField& p,
    volVectorField& U,
    surfaceScalarField& phi
)
:
    mesh_(mesh),
    p_(p),
    U_(U),
    phi_(phi),
    d_x(nullptr),
    d_b(nullptr),
    d_r(nullptr),
    d_rowPtr(nullptr),
    d_colInd(nullptr),
    d_values(nullptr),
    nCells_(mesh.nCells()),
    nnz_(0),
    initialized_(false)
{
    initializeHIP();
}

hipSIMPLE::~hipSIMPLE()
{
    cleanup();
}

void hipSIMPLE::initializeHIP()
{
    // Create rocSPARSE handle
    rocsparse_create_handle(&handle_);
    
    // Create matrix descriptor
    rocsparse_create_mat_descr(&descr_);
    rocsparse_set_mat_index_base(descr_, rocsparse_index_base_zero);
    rocsparse_set_mat_type(descr_, rocsparse_matrix_type_general);
    
    // Create rocBLAS handle for dot products
    rocblas_create_handle(&blas_handle_);
    
    // Allocate device vectors
    size_t vecBytes = nCells_ * sizeof(float);
    hipMalloc(&d_x, vecBytes);
    hipMalloc(&d_b, vecBytes);
    hipMalloc(&d_r, vecBytes);
    
    Info<< "HIP initialization complete" << nl
        << "  Cells: " << nCells_ << nl
        << "  Device memory allocated: " << 3*vecBytes/1024/1024 << " MB" << endl;
    
    // Get GPU info
    hipDeviceProp_t prop;
    hipGetDeviceProperties(&prop, 0);
    Info<< "  GPU: " << prop.name << nl
        << "  GPU memory: " << prop.totalGlobalMem/1024/1024 << " MB" << endl;
    
    initialized_ = true;
}

void hipSIMPLE::convertToCSR(const lduMatrix& matrix)
{
    const lduAddressing& addr = matrix.lduAddr();
    const labelUList& upperAddr = addr.upperAddr();
    const labelUList& lowerAddr = addr.lowerAddr();
    const scalarField& diag = matrix.diag();
    const scalarField& upper = matrix.upper();
    const scalarField& lower = matrix.lower();
    
    label nFaces = upperAddr.size();
    
    // Clear previous data
    rowPtr_.clear();
    colInd_.clear();
    values_.clear();
    diag_.clear();
    
    // Build CSR format - more efficient construction
    rowPtr_.resize(nCells_ + 1, 0);
    
    // Count non-zeros per row first
    std::vector<label> nnzPerRow(nCells_, 1); // Initialize with diagonal
    
    for (label face = 0; face < nFaces; face++)
    {
        nnzPerRow[lowerAddr[face]]++; // Upper contribution
        nnzPerRow[upperAddr[face]]++; // Lower contribution
    }
    
    // Build row pointers
    label totalNnz = 0;
    for (label cell = 0; cell < nCells_; cell++)
    {
        rowPtr_[cell] = totalNnz;
        totalNnz += nnzPerRow[cell];
    }
    rowPtr_[nCells_] = totalNnz;
    nnz_ = totalNnz;
    
    // Allocate storage
    colInd_.resize(nnz_);
    values_.resize(nnz_);
    diag_.resize(nCells_);
    
    // Fill matrix data
    std::vector<label> currentPos = rowPtr_;
    
    for (label cell = 0; cell < nCells_; cell++)
    {
        std::vector<std::pair<label, scalar>> rowEntries;
        
        // Collect all entries for this row
        for (label face = 0; face < nFaces; face++)
        {
            if (lowerAddr[face] == cell)
                rowEntries.push_back({upperAddr[face], upper[face]});
            if (upperAddr[face] == cell)
                rowEntries.push_back({lowerAddr[face], lower[face]});
        }
        
        // Add diagonal
        rowEntries.push_back({cell, diag[cell]});
        diag_[cell] = diag[cell];
        
        // Sort by column index
        std::sort(rowEntries.begin(), rowEntries.end());
        
        // Store in CSR format
        label pos = rowPtr_[cell];
        for (const auto& entry : rowEntries)
        {
            colInd_[pos] = entry.first;
            values_[pos] = static_cast<float>(entry.second);
            pos++;
        }
    }
    
    // Transfer to device
    size_t matBytes = values_.size() * sizeof(float);
    size_t idxBytes = colInd_.size() * sizeof(int);
    size_t rowBytes = rowPtr_.size() * sizeof(int);
    size_t diagBytes = diag_.size() * sizeof(float);
    
    if (d_values) hipFree(d_values);
    if (d_colInd) hipFree(d_colInd);
    if (d_rowPtr) hipFree(d_rowPtr);
    if (d_diag) hipFree(d_diag);
    
    hipMalloc(&d_values, matBytes);
    hipMalloc(&d_colInd, idxBytes);
    hipMalloc(&d_rowPtr, rowBytes);
    hipMalloc(&d_diag, diagBytes);
    
    hipMemcpy(d_values, values_.data(), matBytes, hipMemcpyHostToDevice);
    hipMemcpy(d_colInd, colInd_.data(), idxBytes, hipMemcpyHostToDevice);
    hipMemcpy(d_rowPtr, rowPtr_.data(), rowBytes, hipMemcpyHostToDevice);
    hipMemcpy(d_diag, diag_.data(), diagBytes, hipMemcpyHostToDevice);
}

void hipSIMPLE::solveHIP
(
    volScalarField& psi,
    const volScalarField& source,
    const dictionary& solverControls
)
{
    label maxIter = solverControls.lookupOrDefault<label>("maxIter", 1000);
    scalar tolerance = solverControls.lookupOrDefault<scalar>("tolerance", 1e-6);
    
    // Copy source to device
    scalarField b = source.primitiveField();
    std::vector<float> b_host(nCells_);
    for (label i = 0; i < nCells_; i++)
        b_host[i] = static_cast<float>(b[i]);
    
    hipMemcpy(d_b, b_host.data(), nCells_*sizeof(float), hipMemcpyHostToDevice);
    
    // Initial guess from current field
    scalarField x0 = psi.primitiveField();
    std::vector<float> x_host(nCells_);
    for (label i = 0; i < nCells_; i++)
        x_host[i] = static_cast<float>(x0[i]);
    
    hipMemcpy(d_x, x_host.data(), nCells_*sizeof(float), hipMemcpyHostToDevice);
    
    // Time the GPU solver
    hipEvent_t start, stop;
    hipEventCreate(&start);
    hipEventCreate(&stop);
    hipEventRecord(start, 0);
    
    // Solve with PCG
    label finalIter = PCG(d_x, d_b, maxIter, tolerance);
    
    hipEventRecord(stop, 0);
    hipEventSynchronize(stop);
    float ms = 0.0f;
    hipEventElapsedTime(&ms, start, stop);
    
    Info<< "  GPU solver time: " << ms << " ms (" << finalIter << " iterations)" << endl;
    
    // Copy solution back
    hipMemcpy(x_host.data(), d_x, nCells_*sizeof(float), hipMemcpyDeviceToHost);
    
    scalarField& psiRef = psi.primitiveFieldRef();
    for (label i = 0; i < nCells_; i++)
        psiRef[i] = static_cast<scalar>(x_host[i]);
    
    psi.correctBoundaryConditions();
    
    hipEventDestroy(start);
    hipEventDestroy(stop);
}

__global__ void vecAdd(float* z, const float* x, const float* y, float alpha, int n)
{
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i < n) z[i] = x[i] + alpha * y[i];
}

__global__ void vecScale(float* x, float alpha, int n)
{
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i < n) x[i] *= alpha;
}

__global__ void jacobiPrecond(float* z, const float* r, const float* diag, int n)
{
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i < n) {
        z[i] = (diag[i] != 0.0f) ? r[i] / diag[i] : r[i];
    }
}

label hipSIMPLE::PCG(float* x, const float* b, int maxIter, float tol)
{
    float *d_p, *d_Ap, *d_z;
    hipMalloc(&d_p, nCells_ * sizeof(float));
    hipMalloc(&d_Ap, nCells_ * sizeof(float));
    hipMalloc(&d_z, nCells_ * sizeof(float));
    
    int blockSize = 256;
    int numBlocks = (nCells_ + blockSize - 1) / blockSize;
    
    float alpha = 1.0f, beta = 0.0f;
    
    // r = b - A*x
    rocsparse_scsrmv(handle_, rocsparse_operation_none,
                     nCells_, nCells_, nnz_, &alpha, descr_,
                     d_values, d_rowPtr, d_colInd, x, &beta, d_r);
    
    hipLaunchKernelGGL(vecAdd, dim3(numBlocks), dim3(blockSize), 0, 0,
                       d_r, b, d_r, -1.0f, nCells_);
    
    // Jacobi preconditioner: z = r / diag(A)
    hipLaunchKernelGGL(jacobiPrecond, dim3(numBlocks), dim3(blockSize), 0, 0,
                       d_z, d_r, d_diag, nCells_);
    
    // p = z
    hipMemcpy(d_p, d_z, nCells_ * sizeof(float), hipMemcpyDeviceToDevice);
    
    float rz_old, rz_new;
    rocblas_sdot(blas_handle_, nCells_, d_r, 1, d_z, 1, &rz_old);
    
    float residual = 0.0f;
    label iter;
    
    for (iter = 0; iter < maxIter; iter++)
    {
        // Ap = A*p
        rocsparse_scsrmv(handle_, rocsparse_operation_none,
                        nCells_, nCells_, nnz_, &alpha, descr_,
                        d_values, d_rowPtr, d_colInd, d_p, &beta, d_Ap);
        
        // pAp = p'*Ap
        float pAp;
        rocblas_sdot(blas_handle_, nCells_, d_p, 1, d_Ap, 1, &pAp);
        
        // alpha = rz / pAp
        float step_alpha = rz_old / (pAp + 1e-20f);
        
        // x = x + alpha*p
        hipLaunchKernelGGL(vecAdd, dim3(numBlocks), dim3(blockSize), 0, 0,
                          x, x, d_p, step_alpha, nCells_);
        
        // r = r - alpha*Ap
        hipLaunchKernelGGL(vecAdd, dim3(numBlocks), dim3(blockSize), 0, 0,
                          d_r, d_r, d_Ap, -step_alpha, nCells_);
        
        // Check convergence: ||r||
        rocblas_snrm2(blas_handle_, nCells_, d_r, 1, &residual);
        
        if (residual < tol)
        {
            break;
        }
        
        // z = M^-1 * r (Jacobi preconditioner)
        hipLaunchKernelGGL(jacobiPrecond, dim3(numBlocks), dim3(blockSize), 0, 0,
                          d_z, d_r, d_diag, nCells_);
        
        // rz_new = r'*z
        rocblas_sdot(blas_handle_, nCells_, d_r, 1, d_z, 1, &rz_new);
        
        // beta = rz_new / rz_old
        float pcg_beta = rz_new / (rz_old + 1e-20f);
        
        // p = z + beta*p
        hipLaunchKernelGGL(vecScale, dim3(numBlocks), dim3(blockSize), 0, 0,
                          d_p, pcg_beta, nCells_);
        hipLaunchKernelGGL(vecAdd, dim3(numBlocks), dim3(blockSize), 0, 0,
                          d_p, d_z, d_p, 1.0f, nCells_);
        
        rz_old = rz_new;
        
        if (iter % 50 == 0)
        {
            Info<< "    Iteration " << iter << ", residual = " << residual << endl;
        }
    }
    
    hipFree(d_p);
    hipFree(d_Ap);
    hipFree(d_z);
    
    return iter;
}

void hipSIMPLE::cleanup()
{
    if (initialized_)
    {
        if (d_x) hipFree(d_x);
        if (d_b) hipFree(d_b);
        if (d_r) hipFree(d_r);
        if (d_values) hipFree(d_values);
        if (d_colInd) hipFree(d_colInd);
        if (d_rowPtr) hipFree(d_rowPtr);
        if (d_diag) hipFree(d_diag);
        
        rocsparse_destroy_mat_descr(descr_);
        rocsparse_destroy_handle(handle_);
        rocblas_destroy_handle(blas_handle_);
        
        initialized_ = false;
    }
}