#!/bin/bash
# One-command build script for simpleHIPFoam
# Usage: ./quick_build.sh

set -e

echo "================================================"
echo "  simpleHIPFoam Quick Build"
echo "================================================"
echo ""

# Load environments and build in a subshell
(
    # Source OpenFOAM
    source /usr/lib/openfoam/openfoam2412/etc/bashrc
    
    # Setup ROCm
    export ROCM_PATH=/opt/rocm
    export PATH=$ROCM_PATH/bin:$PATH
    export LD_LIBRARY_PATH=$ROCM_PATH/lib:$LD_LIBRARY_PATH
    
    # Now run the actual build
    bash build.sh
)

echo ""
echo "Build complete! Check output above for status."