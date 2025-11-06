#!/bin/bash
# ABSOLUTE_BUILD.sh - Force build with explicit environment loading

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=========================================="
echo "  ABSOLUTE BUILD - Force Environment"
echo -e "==========================================${NC}\n"

# 1. Find OpenFOAM
FOAM_DIR="/home/indigo/OpenFOAM/OpenFOAM-v2412"
if [ ! -d "$FOAM_DIR" ]; then
    echo -e "${RED}ERROR: OpenFOAM not found at $FOAM_DIR${NC}"
    exit 1
fi

echo "OpenFOAM: $FOAM_DIR"

# 2. CRITICAL: Source bashrc in a way that actually works
echo "Setting up OpenFOAM environment MANUALLY (no bashrc)..."

# MANUAL environment setup - NO SOURCING BASHRC
export WM_PROJECT="OpenFOAM"
export WM_PROJECT_DIR="$FOAM_DIR"
export WM_PROJECT_VERSION="v2412"

# Compiler settings
export WM_COMPILER="Gcc"
export WM_COMPILER_TYPE="system"
export WM_COMPILE_OPTION="Opt"
export WM_PRECISION_OPTION="DP"
export WM_LABEL_SIZE="32"
export WM_OPTIONS="linux64GccDPInt32Opt"

# Paths
export FOAM_INST_DIR="$HOME/OpenFOAM"
export FOAM_SRC="$WM_PROJECT_DIR/src"
export FOAM_APPBIN="$WM_PROJECT_DIR/platforms/$WM_OPTIONS/bin"
export FOAM_LIBBIN="$WM_PROJECT_DIR/platforms/$WM_OPTIONS/lib"
export FOAM_EXT_LIBBIN="$WM_THIRD_PARTY_DIR/platforms/$WM_OPTIONS/lib"

# User directories
export FOAM_USER_APPBIN="$HOME/OpenFOAM/$(whoami)-$WM_PROJECT_VERSION/platforms/$WM_OPTIONS/bin"
export FOAM_USER_LIBBIN="$HOME/OpenFOAM/$(whoami)-$WM_PROJECT_VERSION/platforms/$WM_OPTIONS/lib"

# wmake directories
export WM_DIR="$WM_PROJECT_DIR/wmake"
export WM_PROJECT_USER_DIR="$HOME/OpenFOAM/$(whoami)-$WM_PROJECT_VERSION"

# LIB_SRC is critical for Make/options
export LIB_SRC="$FOAM_SRC"

# Add to PATH
export PATH="$FOAM_APPBIN:$WM_DIR:$PATH"
export LD_LIBRARY_PATH="$FOAM_LIBBIN:$FOAM_EXT_LIBBIN:$FOAM_USER_LIBBIN:$LD_LIBRARY_PATH"

# MPI (set to dummy to avoid MPI issues)
export WM_MPLIB="SYSTEMOPENMPI"
export MPI_ARCH_PATH="/usr/lib/x86_64-linux-gnu/openmpi"

# Create user directories
mkdir -p "$FOAM_USER_APPBIN" "$FOAM_USER_LIBBIN"

# Verify critical variables are set
if [ -z "$WM_PROJECT_DIR" ] || [ -z "$FOAM_SRC" ] || [ -z "$LIB_SRC" ]; then
    echo -e "${RED}ERROR: Critical environment variables not set!${NC}"
    exit 1
fi

echo "  WM_PROJECT_DIR: $WM_PROJECT_DIR"
echo "  FOAM_SRC: $FOAM_SRC"
echo "  WM_OPTIONS: $WM_OPTIONS"
echo "  WM_COMPILER: $WM_COMPILER"

# 3. Verify wmake is available
if ! command -v wmake &> /dev/null; then
    echo -e "${RED}ERROR: wmake not found in PATH!${NC}"
    echo "PATH: $PATH"
    exit 1
fi

echo "  wmake: $(which wmake)"

# 4. Verify fvCFD.H exists
if [ ! -f "$FOAM_SRC/finiteVolume/lnInclude/fvCFD.H" ]; then
    echo -e "${RED}ERROR: fvCFD.H not found!${NC}"
    exit 1
fi

echo -e "${GREEN}✓ fvCFD.H verified${NC}"

# 5. Setup ROCm
export ROCM_PATH=/opt/rocm
export PATH=$ROCM_PATH/bin:$PATH
export LD_LIBRARY_PATH=$ROCM_PATH/lib:$LD_LIBRARY_PATH

echo ""
echo "Creating Make/options..."

# 6. Create Make/options using OpenFOAM variables (not absolute paths)
# This is the KEY fix - use $(LIB_SRC) not absolute paths
cat > applications/solvers/simpleHIPFoam/Make/options << 'EOF'
EXE_INC = \
    -I$(LIB_SRC)/finiteVolume/lnInclude \
    -I$(LIB_SRC)/meshTools/lnInclude \
    -I$(LIB_SRC)/sampling/lnInclude \
    -I$(LIB_SRC)/TurbulenceModels/turbulenceModels/lnInclude \
    -I$(LIB_SRC)/TurbulenceModels/incompressible/lnInclude \
    -I$(LIB_SRC)/transportModels \
    -I$(LIB_SRC)/transportModels/incompressible/singlePhaseTransportModel \
    -I$(LIB_SRC)/dynamicMesh/lnInclude \
    -I$(LIB_SRC)/dynamicFvMesh/lnInclude \
    -I/opt/rocm/include \
    -I/opt/rocm/include/hip \
    -I/opt/rocm/include/rocsparse \
    -I/opt/rocm/include/rocblas

EXE_LIBS = \
    -lfiniteVolume \
    -lfvOptions \
    -lmeshTools \
    -lsampling \
    -lturbulenceModels \
    -lincompressibleTurbulenceModels \
    -lincompressibleTransportModels \
    -ldynamicMesh \
    -ldynamicFvMesh \
    -L/opt/rocm/lib \
    -lamdhip64 \
    -lrocsparse \
    -lrocblas

c++FLAGS = -std=c++14 -O3 -fPIC -D__HIP_PLATFORM_AMD__
EOF

echo "✓ Make/options created"

# 7. Create output directory
FOAM_USER_APPBIN="$HOME/OpenFOAM/$(whoami)-v2412/platforms/$WM_OPTIONS/bin"
mkdir -p "$FOAM_USER_APPBIN"
export FOAM_USER_APPBIN

echo "  Output: $FOAM_USER_APPBIN"
echo ""

# 8. Build
cd applications/solvers/simpleHIPFoam

echo "Cleaning..."
rm -rf Make/linux64* 2>/dev/null || true

echo ""
echo "Building with wmake..."
echo ""

# Run wmake with the properly loaded environment
wmake 2>&1 | tee ../../../build.log

BUILD_STATUS=${PIPESTATUS[0]}

echo ""
if [ $BUILD_STATUS -eq 0 ]; then
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
        echo "Searching for executable..."
        find "$HOME/OpenFOAM" -name "simpleHIPFoam" -type f 2>/dev/null | head -3
    fi
else
    echo -e "${RED}=========================================="
    echo "  ✗✗✗ BUILD FAILED ✗✗✗"
    echo -e "==========================================${NC}"
    echo ""
    echo "Compiler command used:"
    grep "^g++" ../../../build.log | head -1
    echo ""
    echo "Last 20 lines:"
    tail -20 ../../../build.log
    exit 1
fi