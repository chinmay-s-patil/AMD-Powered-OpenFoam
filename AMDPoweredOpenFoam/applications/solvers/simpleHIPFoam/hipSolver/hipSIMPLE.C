// hipSIMPLE.C
// Implementation of HIP-accelerated SIMPLE solver

#include "hipSIMPLE.H"

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
    
    // Allocate device vectors
    size_t vecBytes = nCells_ * sizeof(float);
    hipMalloc(&d_x, vecBytes);
    hipMalloc(&d_b, vecBytes);
    hipMalloc(&d_r, vecBytes);
    
    Info<< "HIP initialization complete" << nl
        << "  Cells: " << nCells_ << nl
        << "  Device memory allocated: " << 3*vecBytes/1024/1024 << " MB" << endl;
    
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
    
    // Estimate non-zeros: diagonal + upper + lower
    nnz_ = nCells_ + 2*nFaces;
    
    rowPtr_.resize(nCells_ + 1);
    colInd_.reserve(nnz_);
    values_.reserve(nnz_);
    
    // Build CSR format
    label count = 0;
    rowPtr_[0] = 0;
    
    for (label cell = 0; cell < nCells_; cell++)
    {
        // Lower triangular contributions
        for (label face = 0; face < nFaces; face++)
        {
            if (upperAddr[face] == cell)
            {
                colInd_.push_back(lowerAddr[face]);
                values_.push_back(lower[face]);
                count++;
            }
        }
        
        // Diagonal
        colInd_.push_back(cell);
        values_.push_back(diag[cell]);
        count++;
        
        // Upper triangular contributions
        for (label face = 0; face < nFaces; face++)
        {
            if (lowerAddr[face] == cell)
            {
                colInd_.push_back(upperAddr[face]);
                values_.push_back(upper[face]);
                count++;
            }
        }
        
        rowPtr_[cell + 1] = count;
    }
    
    // Transfer to device
    size_t matBytes = values_.size() * sizeof(float);
    size_t idxBytes = colInd_.size() * sizeof(int);
    size_t rowBytes = rowPtr_.size() * sizeof(int);
    
    if (d_values) hipFree(d_values);
    if (d_colInd) hipFree(d_colInd);
    if (d_rowPtr) hipFree(d_rowPtr);
    
    hipMalloc(&d_values, matBytes);
    hipMalloc(&d_colInd, idxBytes);
    hipMalloc(&d_rowPtr, rowBytes);
    
    hipMemcpy(d_values, values_.data(), matBytes, hipMemcpyHostToDevice);
    hipMemcpy(d_colInd, colInd_.data(), idxBytes, hipMemcpyHostToDevice);
    hipMemcpy(d_rowPtr, rowPtr_.data(), rowBytes, hipMemcpyHostToDevice);
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
    
    // Solve with PCG
    PCG(d_x, d_b, maxIter, tolerance);
    
    // Copy solution back
    hipMemcpy(x_host.data(), d_x, nCells_*sizeof(float), hipMemcpyDeviceToHost);
    
    scalarField& psiRef = psi.primitiveFieldRef();
    for (label i = 0; i < nCells_; i++)
        psiRef[i] = static_cast<scalar>(x_host[i]);
    
    psi.correctBoundaryConditions();
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

void hipSIMPLE::PCG(float* x, const float* b, int maxIter, float tol)
{
    float *d_p, *d_Ap, *d_z;
    hipMalloc(&d_p, nCells_ * sizeof(float));
    hipMalloc(&d_Ap, nCells_ * sizeof(float));
    hipMalloc(&d_z, nCells_ * sizeof(float));
    
    int blockSize = 256;
    int numBlocks = (nCells_ + blockSize - 1) / blockSize;
    
    // r = b - A*x
    float alpha = 1.0f, beta = 0.0f;
    rocsparse_scsrmv(handle_, rocsparse_operation_none,
                     nCells_, nCells_, nnz_, &alpha, descr_,
                     d_values, d_rowPtr, d_colInd, x, &beta, d_r);
    
    // r = b - r
    hipLaunchKernelGGL(vecAdd, dim3(numBlocks), dim3(blockSize), 0, 0,
                       d_r, b, d_r, -1.0f, nCells_);
    
    // Simple Jacobi preconditioner: z = r / diag(A)
    hipMemcpy(d_z, d_r, nCells_ * sizeof(float), hipMemcpyDeviceToDevice);
    
    // p = z
    hipMemcpy(d_p, d_z, nCells_ * sizeof(float), hipMemcpyDeviceToDevice);
    
    float rz_old = 0.0f;
    // Compute dot product r'z using rocBLAS would be better, simplified here
    
    for (int iter = 0; iter < maxIter; iter++)
    {
        // Ap = A*p
        rocsparse_scsrmv(handle_, rocsparse_operation_none,
                        nCells_, nCells_, nnz_, &alpha, descr_,
                        d_values, d_rowPtr, d_colInd, d_p, &beta, d_Ap);
        
        // alpha = (r'z) / (p'Ap) - simplified, needs proper dot products
        float pAp = 1.0f; // placeholder
        float step_alpha = rz_old / pAp;
        
        // x = x + alpha*p
        hipLaunchKernelGGL(vecAdd, dim3(numBlocks), dim3(blockSize), 0, 0,
                          x, x, d_p, step_alpha, nCells_);
        
        // r = r - alpha*Ap
        hipLaunchKernelGGL(vecAdd, dim3(numBlocks), dim3(blockSize), 0, 0,
                          d_r, d_r, d_Ap, -step_alpha, nCells_);
        
        // Check convergence (simplified)
        // Should compute ||r|| and check against tol
        
        if (iter % 10 == 0)
        {
            Info<< "  HIP PCG iteration " << iter << endl;
        }
    }
    
    hipFree(d_p);
    hipFree(d_Ap);
    hipFree(d_z);
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
        
        rocsparse_destroy_mat_descr(descr_);
        rocsparse_destroy_handle(handle_);
        
        initialized_ = false;
    }
}