#!/bin/bash
# Quick fix for OpenFOAM build - Replace $(LIB_SRC) with actual paths

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=========================================="
echo "  Fixing OpenFOAM Build Paths"
echo "=========================================="
echo ""

# Detect OpenFOAM installation
FOAM_SRC="/usr/lib/openfoam/openfoam2406/src"

if [ ! -d "$FOAM_SRC" ]; then
    echo -e "${RED}Error: OpenFOAM not found at $FOAM_SRC${NC}"
    echo "Please set FOAM_SRC manually in this script"
    exit 1
fi

echo "Using OpenFOAM source: $FOAM_SRC"
echo ""

# Navigate to solver directory
cd applications/solvers/simpleHIPFoam

# Clean previous build
echo "Cleaning previous build..."
rm -rf Make/linux64GccDPInt32Opt 2>/dev/null || true

# Create Make/options with ABSOLUTE paths
echo "Creating Make/options with absolute paths..."
cat > Make/options << EOF
EXE_INC = \\
    -I/usr/lib/openfoam/openfoam2406/src/finiteVolume/lnInclude \\
    -I/usr/lib/openfoam/openfoam2406/src/OpenFOAM/lnInclude \\
    -I/usr/lib/openfoam/openfoam2406/src/OSspecific/POSIX/lnInclude \\
    -I/usr/lib/openfoam/openfoam2406/src/meshTools/lnInclude \\
    -I/usr/lib/openfoam/openfoam2406/src/sampling/lnInclude \\
    -I/usr/lib/openfoam/openfoam2406/src/TurbulenceModels/turbulenceModels/lnInclude \\
    -I/usr/lib/openfoam/openfoam2406/src/TurbulenceModels/incompressible/lnInclude \\
    -I/usr/lib/openfoam/openfoam2406/src/transportModels \\
    -I/usr/lib/openfoam/openfoam2406/src/transportModels/incompressible/singlePhaseTransportModel \\
    -I/usr/lib/openfoam/openfoam2406/src/dynamicMesh/lnInclude \\
    -I/usr/lib/openfoam/openfoam2406/src/dynamicFvMesh/lnInclude \\
    -I/opt/rocm/include \\
    -I/opt/rocm/include/hip \\
    -I/opt/rocm/include/rocsparse \\
    -I/opt/rocm/include/rocblas

EXE_LIBS = \\
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

echo -e "${GREEN}✓ Make/options created${NC}"
echo ""
echo "First include path:"
head -2 Make/options | tail -1
echo ""

# Verify fvCFD.H exists
if [ -f "$FOAM_SRC/finiteVolume/lnInclude/fvCFD.H" ]; then
    echo -e "${GREEN}✓ fvCFD.H found at: $FOAM_SRC/finiteVolume/lnInclude/fvCFD.H${NC}"
else
    echo -e "${RED}✗ fvCFD.H NOT FOUND!${NC}"
    echo "Your OpenFOAM installation may be incomplete"
    exit 1
fi

echo ""
echo "Building with wmake..."
echo ""

# Source OpenFOAM environment if not already loaded
if [ -z "$WM_PROJECT_DIR" ]; then
    export WM_PROJECT_DIR="/usr/lib/openfoam/openfoam2406"
    export FOAM_APPBIN="$WM_PROJECT_DIR/platforms/linux64GccDPInt32Opt/bin"
    export FOAM_LIBBIN="$WM_PROJECT_DIR/platforms/linux64GccDPInt32Opt/lib"
    export WM_DIR="$WM_PROJECT_DIR/wmake"
    export FOAM_USER_APPBIN="$HOME/OpenFOAM/$(whoami)-v2406/platforms/linux64GccDPInt32Opt/bin"
    export PATH="$FOAM_APPBIN:$WM_DIR:$PATH"
    export LD_LIBRARY_PATH="$FOAM_LIBBIN:$LD_LIBRARY_PATH"
    mkdir -p "$FOAM_USER_APPBIN" 2>/dev/null || true
fi

# Build
wmake 2>&1 | tee ../../../build_fixed.log

if [ ${PIPESTATUS[0]} -eq 0 ]; then
    echo ""
    echo -e "${GREEN}=========================================="
    echo "  ✓✓✓ BUILD SUCCESSFUL! ✓✓✓"
    echo -e "==========================================${NC}"
    echo ""
    
    if [ -f "$FOAM_USER_APPBIN/simpleHIPFoam" ]; then
        echo "Executable created:"
        ls -lh "$FOAM_USER_APPBIN/simpleHIPFoam"
        echo ""
        echo "Test it:"
        echo "  $FOAM_USER_APPBIN/simpleHIPFoam -help"
    fi
else
    echo ""
    echo -e "${RED}=========================================="
    echo "  ✗✗✗ BUILD FAILED ✗✗✗"
    echo -e "==========================================${NC}"
    echo ""
    echo "Check build_fixed.log for details"
    tail -20 ../../../build_fixed.log
    exit 1
fi