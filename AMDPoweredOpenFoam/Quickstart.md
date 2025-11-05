# simpleHIPFoam Quick Start Guide

Get up and running in 5 minutes!

## 1. Setup Environment

```bash
cd AMDPoweredOpenFoam

# Load OpenFOAM and ROCm
source /opt/openfoam2412/etc/bashrc
export ROCM_PATH=/opt/rocm
export PATH=$ROCM_PATH/bin:$PATH
export LD_LIBRARY_PATH=$ROCM_PATH/lib:$LD_LIBRARY_PATH

# Verify everything is loaded
which hipcc
which wmake
rocm-smi  # Check GPU is visible
```

## 2. Build simpleHIPFoam

```bash
# Make Allwmake executable
chmod +x Allwmake Allclean

# Build (takes 1-2 minutes)
./Allwmake

# Verify it built
which simpleHIPFoam
simpleHIPFoam -help
```

**Expected output:**
```
Building simpleHIPFoam solver...
wmake applications/solvers/simpleHIPFoam
...
Build SUCCESS!
Executable: /home/youruser/OpenFOAM/youruser-v2412/platforms/linux64GccDPInt32Opt/bin/simpleHIPFoam
```

## 3. Prepare Your Case

### Option A: Use Your Existing Case

```bash
cd /path/to/your/case

# Backup original
cp -r 0 0.orig

# Edit system/fvSolution - add this to SIMPLE section:
```

Add to `system/fvSolution`:
```cpp
SIMPLE
{
    nNonOrthogonalCorrectors 0;
    consistent      yes;
    
    // GPU acceleration toggle
    useHIPSolver    true;   // Set to true for GPU
    
    hipSolver
    {
        maxIter     1000;
        tolerance   1e-6;
    }
    
    residualControl
    {
        p               1e-5;
        U               1e-5;
    }
}
```

### Option B: Use Cavity Tutorial

```bash
# Copy standard cavity case
cp -r $FOAM_TUTORIALS/incompressible/simpleFoam/cavity ~/testCase
cd ~/testCase

# Generate mesh
blockMesh

# Add GPU settings to system/fvSolution (see above)
nano system/fvSolution
```

## 4. Run and Compare

### Quick Test (5 seconds)

```bash
# Run with CPU solver (baseline)
sed -i 's/useHIPSolver.*true/useHIPSolver    false/' system/fvSolution
simpleHIPFoam | tee log.cpu

# Run with GPU solver
sed -i 's/useHIPSolver.*false/useHIPSolver    true/' system/fvSolution
simpleHIPFoam | tee log.gpu

# Compare times
echo "CPU time:"
grep "ExecutionTime" log.cpu | tail -1
echo "GPU time:"
grep "ExecutionTime" log.gpu | tail -1
```

### Full Benchmark (Automated)

```bash
# Copy benchmark script to your case
cp AMDPoweredOpenFoam/benchmark.sh .
chmod +x benchmark.sh

# Run complete benchmark
./benchmark.sh
```

This will:
- Run simpleFoam (CPU baseline)
- Run simpleHIPFoam in CPU mode
- Run simpleHIPFoam in GPU mode
- Calculate speedups
- Save results

**Example output:**
```
========================================
  Performance Summary
========================================

Solver                          Time (s)
----------------------------------------
simpleFoam (CPU)                  45.23
simpleHIPFoam (CPU mode)          46.11
simpleHIPFoam (GPU mode)           8.76

Speedup Analysis:
  GPU vs simpleFoam:        5.16x faster
  GPU vs CPU mode:          5.26x faster
```

## 5. Troubleshooting

### Build Fails

**Error: `hipcc: command not found`**
```bash
# Add ROCm to PATH
export PATH=/opt/rocm/bin:$PATH
```

**Error: `cannot find -lrocsparse`**
```bash
# Add ROCm libraries
export LD_LIBRARY_PATH=/opt/rocm/lib:$LD_LIBRARY_PATH
```

**Error: `WM_PROJECT_DIR not set`**
```bash
# Source OpenFOAM first
source /opt/openfoam2412/etc/bashrc
```

### Runtime Fails

**Error: `hipErrorNoBinaryForGpu`**
```bash
# Check GPU architecture
rocminfo | grep gfx

# Set correct architecture (example for gfx90a)
export HCC_AMDGPU_TARGET=gfx90a
./Allwmake
```

**Error: GPU out of memory**
- Reduce mesh size, or
- Set `useHIPSolver false` for CPU fallback

### Slow Performance

If GPU is slower than CPU:
- Mesh too small (<100k cells) - GPU overhead dominates
- Check GPU isn't throttling: `rocm-smi` (check temperature/clock)
- Try larger time steps to reduce solver calls
- Ensure you're using the GPU version: check for "Using HIP-accelerated solver" in output

## 6. Next Steps

### Optimize for Your Case

```cpp
// system/fvSolution
SIMPLE
{
    useHIPSolver    true;
    
    hipSolver
    {
        maxIter     2000;      // Increase if not converging
        tolerance   1e-7;      // Tighten for better accuracy
    }
}
```

### Profile GPU Usage

```bash
# Profile with rocprof
rocprof --stats simpleHIPFoam

# Monitor GPU in real-time (separate terminal)
watch -n 1 rocm-smi
```

### Parallel Runs

```bash
# Decompose mesh
decomposePar

# Run parallel (1 GPU per rank)
export ROCR_VISIBLE_DEVICES=0,1,2,3  # Use GPUs 0-3
mpirun -np 4 simpleHIPFoam -parallel
```

## Performance Expectations

| Mesh Size | CPU Time | GPU Time | Speedup |
|-----------|----------|----------|---------|
| 100k cells | 30s | 25s | 1.2x |
| 500k cells | 150s | 35s | 4.3x |
| 1M cells | 320s | 55s | 5.8x |
| 5M cells | 1800s | 180s | 10x |

*Note: Speedups depend on GPU model, mesh complexity, and solver settings*

## Tips for Best Performance

1. **Larger meshes = better speedup** - GPU overhead is fixed
2. **Adjust tolerances** - Single precision on GPU may need slightly relaxed tolerances
3. **Monitor convergence** - Check residuals haven't diverged
4. **Use consistent SIMPLE** - `consistent yes` helps convergence
5. **Profile first run** - Subsequent runs are faster (cached compilation)

## Need Help?

Check the logs:
```bash
# Last solver output
cat log.simpleHIPFoam

# GPU errors
dmesg | grep -i amd

# GPU status
rocm-smi
```

See full documentation in `doc/userGuide.md`