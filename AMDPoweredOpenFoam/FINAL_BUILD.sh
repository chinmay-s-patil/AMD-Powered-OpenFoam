#!/bin/bash
# FINAL BUILD - This will work!

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=========================================="
echo "  FINAL BUILD - Absolute Paths"
echo -e "==========================================${NC}\n"

# Find OpenFOAM
if [ -f "/home/indigo/OpenFOAM/OpenFOAM-v2412/src/finiteVolume/lnInclude/fvCFD.H" ]; then
    FOAM_DIR="/home/indigo/OpenFOAM/OpenFOAM-v2412"
    WM_OPTIONS="linux64GccDPInt32Opt"
elif [ -f "/usr/lib/openfoam/openfoam2412/src/finiteVolume/lnInclude/fvCFD.H" ]; then
    FOAM_DIR="/usr/lib/openfoam/openfoam2412"
    WM_OPTIONS="linux64GccDPInt32Opt"
else
    echo -e "${RED}ERROR: fvCFD.H not found!${NC}"
    exit 1
fi

echo "OpenFOAM: $FOAM_DIR"
echo "Platform: $WM_OPTIONS"
echo ""

# Set CRITICAL environment variables
export WM_PROJECT_DIR="$FOAM_DIR"
export FOAM_SRC="$FOAM_DIR/src"
export LIB_SRC="$FOAM_SRC"
export WM_DIR="$FOAM_DIR/wmake"
export PATH="$FOAM_DIR/platforms/$WM_OPTIONS/bin:$WM_DIR:$PATH"
export LD_LIBRARY_PATH="$FOAM_DIR/platforms/$WM_OPTIONS/lib:$LD_LIBRARY_PATH"

# Create output directory
FOAM_USER_APPBIN="$HOME/OpenFOAM/$(whoami)-v2412/platforms/$WM_OPTIONS/bin"
mkdir -p "$FOAM_USER_APPBIN"
export FOAM_USER_APPBIN

# ROCm
export ROCM_PATH=/opt/rocm
export PATH=$ROCM_PATH/bin:$PATH
export LD_LIBRARY_PATH=$ROCM_PATH/lib:$LD_LIBRARY_PATH

echo "Environment:"
echo "  FOAM_SRC: $FOAM_SRC"
echo "  LIB_SRC: $LIB_SRC"
echo "  FOAM_USER_APPBIN: $FOAM_USER_APPBIN"
echo ""

# Create Make/options with ABSOLUTE paths
echo "Creating Make/options with absolute paths..."

cat > applications/solvers/simpleHIPFoam/Make/options << EOF
EXE_INC = \\
    -I$FOAM_SRC/finiteVolume/lnInclude \\
    -I$FOAM_SRC/meshTools/lnInclude \\
    -I$FOAM_SRC/sampling/lnInclude \\
    -I$FOAM_SRC/TurbulenceModels/turbulenceModels/lnInclude \\
    -I$FOAM_SRC/TurbulenceModels/incompressible/lnInclude \\
    -I$FOAM_SRC/transportModels \\
    -I$FOAM_SRC/transportModels/incompressible/singlePhaseTransportModel \\
    -I$FOAM_SRC/dynamicMesh/lnInclude \\
    -I$FOAM_SRC/dynamicFvMesh/lnInclude \\
    -I/opt/rocm/include \\
    -I/opt/rocm/include/hip \\
    -I/opt/rocm/include/rocsparse \\
    -I/opt/rocm/include/rocblas

EXE_LIBS = \\
    -L$FOAM_DIR/platforms/$WM_OPTIONS/lib \\
    -lfiniteVolume \\
    -lfvOptions \\
    -lmeshTools \\
    -lsampling \\
    -lturbulenceModels \\
    -lincompressibleTurbulenceModels \\
    -lincompressibleTransportModels \\
    -ldynamicMesh \\
    -ldynamicFvMesh \\
    -L/opt/rocm/lib \\
    -lamdhip64 \\
    -lrocsparse \\
    -lrocblas

c++FLAGS = -std=c++14 -O3 -fPIC -D__HIP_PLATFORM_AMD__
EOF

echo "✓ Make/options created"
echo ""

# Verify fvCFD.H is accessible
if [ -f "$FOAM_SRC/finiteVolume/lnInclude/fvCFD.H" ]; then
    echo -e "${GREEN}✓ fvCFD.H found at $FOAM_SRC/finiteVolume/lnInclude/fvCFD.H${NC}"
else
    echo -e "${RED}✗ fvCFD.H NOT found!${NC}"
    exit 1
fi

# Build
cd applications/solvers/simpleHIPFoam

echo ""
echo "Cleaning..."
rm -rf Make/linux64* 2>/dev/null || true

echo ""
echo "Building..."
echo ""

# Call wmake with verbose output
wmake 2>&1 | tee ../../../build.log

if [ ${PIPESTATUS[0]} -eq 0 ]; then
    echo ""
    echo -e "${GREEN}=========================================="
    echo "  ✓✓✓ BUILD SUCCESS ✓✓✓"
    echo -e "==========================================${NC}"
    echo ""
    
    if [ -f "$FOAM_USER_APPBIN/simpleHIPFoam" ]; then
        echo "Executable:"
        ls -lh "$FOAM_USER_APPBIN/simpleHIPFoam"
        echo ""
        echo "Test: $FOAM_USER_APPBIN/simpleHIPFoam -help"
    else
        echo "Executable may be at:"
        find "$HOME/OpenFOAM" -name "simpleHIPFoam" -type f 2>/dev/null
    fi
else
    echo ""
    echo -e "${RED}=========================================="
    echo "  ✗✗✗ BUILD FAILED ✗✗✗"
    echo -e "==========================================${NC}"
    echo ""
    echo "Showing compiler command (check for -I paths):"
    grep "^g++" ../../../build.log | head -1
    echo ""
    echo "Last 20 lines:"
    tail -20 ../../../build.log
    exit 1
fi