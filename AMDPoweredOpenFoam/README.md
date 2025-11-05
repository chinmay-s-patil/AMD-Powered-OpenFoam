# simpleHIPFoam

HIP/ROCm-accelerated steady-state incompressible flow solver based on OpenFOAM's simpleFoam with GPU acceleration for linear solvers.

## Features

- **Hybrid CPU-GPU Architecture**: Uses OpenFOAM for mesh handling, discretization, and I/O while offloading linear algebra to AMD GPUs
- **SIMPLE Algorithm**: Pressure-velocity coupling for steady-state flows
- **Turbulence Modeling**: Full support for RANS models (k-epsilon, k-omega SST, Spalart-Allmaras)
- **Compatible with OpenFOAM v2412**: Direct drop-in replacement for simpleFoam
- **rocSPARSE Integration**: GPU-accelerated sparse matrix operations
- **Configurable**: Toggle HIP solver on/off via fvSolution dictionary

## Requirements

### Software
- OpenFOAM v2412
- ROCm 5.0+ (tested with 5.7)
- AMD GPU with HIP support
- hipcc compiler
- rocSPARSE library
- rocBLAS library (optional, for optimized dot products)

### Hardware
- AMD GPU (Radeon Instinct MI series, Radeon Pro, or compatible)
- Recommended: 8GB+ GPU memory for large meshes

## Installation

1. **Source OpenFOAM environment:**
```bash
source /opt/openfoam2412/etc/bashrc
```

2. **Set ROCm paths:**
```bash
export ROCM_PATH=/opt/rocm
export PATH=$ROCM_PATH/bin:$PATH
export LD_LIBRARY_PATH=$ROCM_PATH/lib:$LD_LIBRARY_PATH
```

3. **Clone and build:**
```bash
cd simpleHIPFoam
wmake
```

## Project Structure

```
simpleHIPFoam/
├── simpleHIPFoam.C          # Main application
├── hipSIMPLE.H              # HIP solver interface
├── hipSIMPLE.C              # HIP solver implementation
├── createFields.H           # Field initialization
├── UEqn.H                   # Momentum equation
├── pEqn.H                   # Pressure equation with HIP option
├── Make/
│   ├── files                # Source files list
│   └── options              # Compiler and linker options
└── README.md
```

## Usage

### Basic Run

Use exactly like simpleFoam:

```bash
simpleHIPFoam
```

### Enable HIP Acceleration

Edit `system/fvSolution`:

```cpp
SIMPLE
{
    useHIPSolver    true;  // Enable GPU solver
    
    hipSolver
    {
        maxIter     1000;
        tolerance   1e-6;
    }
}
```

### Parallel Execution

```bash
decomposePar
mpirun -np 4 simpleHIPFoam -parallel
```

**Note:** Each MPI rank will use its own GPU if available. Use `ROCR_VISIBLE_DEVICES` to control GPU assignment.

## Example Case

For a cavity flow case:

```bash
# Copy tutorial case
cp -r $FOAM_TUTORIALS/incompressible/simpleFoam/cavity ./testCase
cd testCase

# Run with HIP solver
simpleHIPFoam | tee log.simpleHIPFoam

# Post-process
paraFoam
```

## Performance Tips

1. **GPU Memory**: Monitor with `rocm-smi`. Large meshes (>10M cells) may require multiple GPUs or CPU fallback
2. **Convergence**: GPU solvers use single-precision. Adjust tolerances if needed
3. **First Run**: Initial HIP compilation may be slow; subsequent runs are faster
4. **Profiling**: Use `rocprof` to profile GPU kernels

## Implementation Details

### Matrix Format Conversion

OpenFOAM's `lduMatrix` (lower-diagonal-upper) format is converted to CSR (Compressed Sparse Row) for GPU compatibility:

```cpp
void convertToCSR(const lduMatrix& matrix);
```

### GPU Solver

Preconditioned Conjugate Gradient (PCG) implemented with:
- rocSPARSE for sparse matrix-vector products
- Simple Jacobi preconditioner
- CUDA-style kernels for vector operations

### Memory Management

- Persistent GPU buffers allocated once
- Matrix structure rebuilt when mesh changes
- Automatic cleanup on destruction

## Current Limitations

1. **Single Precision**: GPU solver uses `float` (OpenFOAM uses `double`)
2. **Simple Preconditioner**: Only Jacobi; ILU(0) not yet implemented
3. **Pressure Equation Only**: Momentum equations still use CPU solvers
4. **No Dynamic Mesh**: Mesh motion not supported
5. **Convergence Monitoring**: Simplified residual calculation

## Roadmap

- [ ] Implement proper dot products with rocBLAS
- [ ] Add ILU(0) preconditioner
- [ ] Extend to velocity equations
- [ ] Multi-GPU support via MPI
- [ ] Dynamic mesh handling
- [ ] FP64 option for better accuracy
- [ ] Benchmark suite against simpleFoam

## Troubleshooting

### HIP Runtime Errors

```bash
# Check GPU visibility
rocm-smi

# Test HIP installation
/opt/rocm/bin/hipconfig --version
```

### Linking Errors

Verify ROCm libraries are in `Make/options`:
```makefile
-L/opt/rocm/lib -lamdhip64 -lrocsparse
```

### Performance Issues

- Disable HIP solver for small meshes (<100k cells)
- Check CPU-GPU transfer overhead with profiling
- Ensure GPU isn't throttling (temperature, power)

## References

- OpenFOAM User Guide: https://www.openfoam.com/documentation
- ROCm Documentation: https://rocm.docs.amd.com
- rocSPARSE API: https://rocsparse.readthedocs.io

## License

CC0 1.0 Universal (same as provided LICENSE file)

## Contributing

Contributions welcome! Areas of interest:
- Better preconditioners
- Convergence improvements
- Multi-GPU scaling
- Extended equation support

## Citation

If you use this in research, please cite:
```
simpleHIPFoam: HIP-accelerated SIMPLE solver for OpenFOAM
https://github.com/yourusername/simpleHIPFoam
```