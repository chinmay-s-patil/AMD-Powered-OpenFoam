#!/bin/bash
# Simple build script - no bashrc sourcing to avoid hangs
# Run this from AMDPoweredOpenFoam directory

set -e

echo "================================================"
echo "  simpleHIPFoam Quick Build"
echo "================================================"
echo ""

# Find OpenFOAM
if [ -d "$HOME/OpenFOAM/OpenFOAM-v2412" ]; then
    OF_DIR="$HOME/OpenFOAM/OpenFOAM-v2412"
elif [ -d "/usr/lib/openfoam/openfoam2412" ]; then
    OF_DIR="/usr/lib/openfoam/openfoam2412"
else
    echo "ERROR: OpenFOAM v2412 not found!"
    exit 1
fi

echo "OpenFOAM: $OF_DIR"

# Set environment manually (no sourcing bashrc!)
export WM_PROJECT_DIR="$OF_DIR"
export WM_PROJECT_VERSION="v2412"
export FOAM_SRC="$WM_PROJECT_DIR/src"
export LIB_SRC="$FOAM_SRC"
export FOAM_APPBIN="$WM_PROJECT_DIR/platforms/linux64GccDPInt32Opt/bin"
export FOAM_USER_APPBIN="$HOME/OpenFOAM/$(whoami)-v2412/platforms/linux64GccDPInt32Opt/bin"
export WM_DIR="$WM_PROJECT_DIR/wmake"
export WM_OPTIONS="linux64GccDPInt32Opt"
export PATH="$FOAM_APPBIN:$WM_DIR:$PATH"
export LD_LIBRARY_PATH="$WM_PROJECT_DIR/platforms/$WM_OPTIONS/lib:$LD_LIBRARY_PATH"

# ROCm
export ROCM_PATH=/opt/rocm
export PATH=$ROCM_PATH/bin:$PATH
export LD_LIBRARY_PATH=$ROCM_PATH/lib:$LD_LIBRARY_PATH

# Create output directory
mkdir -p "$FOAM_USER_APPBIN"

echo "Environment set!"
echo ""

# Check critical file
if [ ! -f "$FOAM_SRC/finiteVolume/lnInclude/fvCFD.H" ]; then
    echo "ERROR: fvCFD.H not found at $FOAM_SRC/finiteVolume/lnInclude/"
    echo ""
    echo "Your OpenFOAM installation is incomplete."
    echo "Try: sudo apt-get install openfoam2412-dev openfoam2412-source"
    exit 1
fi

# Check hipcc
if ! command -v hipcc &> /dev/null; then
    echo "ERROR: hipcc not found!"
    echo "Install ROCm first"
    exit 1
fi

echo "All dependencies OK"
echo ""

# Build
cd applications/solvers/simpleHIPFoam

echo "Cleaning..."
rm -rf Make/linux64* 2>/dev/null || true

echo ""
echo "Building..."
echo ""

wmake 2>&1 | tee ../../../build.log

if [ $? -eq 0 ]; then
    echo ""
    echo "✓✓✓ BUILD SUCCESS ✓✓✓"
    echo ""
    ls -lh "$FOAM_USER_APPBIN/simpleHIPFoam" 2>/dev/null || {
        echo "Executable may be at:"
        find "$HOME/OpenFOAM" -name "simpleHIPFoam" 2>/dev/null | head -3
    }
else
    echo ""
    echo "✗✗✗ BUILD FAILED ✗✗✗"
    echo ""
    echo "Last 20 lines:"
    tail -20 ../../../build.log
    exit 1
fi