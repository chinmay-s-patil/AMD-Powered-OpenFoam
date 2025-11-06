#!/bin/bash
# MANUAL_BUILD.sh - Bypass wmake completely and compile manually

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}=========================================="
echo "  MANUAL BUILD - Direct Compilation"
echo -e "==========================================${NC}\n"

# Setup paths
FOAM_DIR="/home/indigo/OpenFOAM/OpenFOAM-v2412"
FOAM_SRC="$FOAM_DIR/src"
WM_OPTIONS="linux64GccDPInt32Opt"
FOAM_LIBBIN="$FOAM_DIR/platforms/$WM_OPTIONS/lib"
FOAM_USER_APPBIN="$HOME/OpenFOAM/indigo-v2412/platforms/$WM_OPTIONS/bin"
ROCM_PATH="/opt/rocm"

# Create output directory
mkdir -p "$FOAM_USER_APPBIN"
mkdir -p "applications/solvers/simpleHIPFoam/Make/$WM_OPTIONS"

echo "Paths:"
echo "  FOAM_SRC: $FOAM_SRC"
echo "  FOAM_LIBBIN: $FOAM_LIBBIN"
echo "  OUTPUT: $FOAM_USER_APPBIN"
echo ""

# Verify headers exist
if [ ! -f "$FOAM_SRC/finiteVolume/lnInclude/fvCFD.H" ]; then
    echo -e "${RED}ERROR: fvCFD.H not found!${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Headers verified${NC}"

cd applications/solvers/simpleHIPFoam

# Clean
rm -rf Make/$WM_OPTIONS/*.o Make/$WM_OPTIONS/*.dep 2>/dev/null || true

echo ""
echo "Compiling simpleHIPFoam.C..."

# Compile simpleHIPFoam.C with ALL include paths explicitly
g++ -std=c++14 \
    -O3 \
    -fPIC \
    -D__HIP_PLATFORM_AMD__ \
    -DWM_DP \
    -DWM_LABEL_SIZE=32 \
    -I. \
    -I$FOAM_SRC/finiteVolume/lnInclude \
    -I$FOAM_SRC/OpenFOAM/lnInclude \
    -I$FOAM_SRC/OSspecific/POSIX/lnInclude \
    -I$FOAM_SRC/meshTools/lnInclude \
    -I$FOAM_SRC/sampling/lnInclude \
    -I$FOAM_SRC/TurbulenceModels/turbulenceModels/lnInclude \
    -I$FOAM_SRC/TurbulenceModels/incompressible/lnInclude \
    -I$FOAM_SRC/transportModels \
    -I$FOAM_SRC/transportModels/incompressible/singlePhaseTransportModel \
    -I$FOAM_SRC/dynamicMesh/lnInclude \
    -I$FOAM_SRC/dynamicFvMesh/lnInclude \
    -I$ROCM_PATH/include \
    -I$ROCM_PATH/include/hip \
    -I$ROCM_PATH/include/rocsparse \
    -I$ROCM_PATH/include/rocblas \
    -c simpleHIPFoam.C \
    -o Make/$WM_OPTIONS/simpleHIPFoam.o

if [ $? -ne 0 ]; then
    echo -e "${RED}✗ Compilation of simpleHIPFoam.C failed${NC}"
    exit 1
fi
echo -e "${GREEN}✓ simpleHIPFoam.o created${NC}"

echo ""
echo "Compiling hipSIMPLE.C..."

# Compile hipSIMPLE.C
g++ -std=c++14 \
    -O3 \
    -fPIC \
    -D__HIP_PLATFORM_AMD__ \
    -DWM_DP \
    -DWM_LABEL_SIZE=32 \
    -I. \
    -I$FOAM_SRC/finiteVolume/lnInclude \
    -I$FOAM_SRC/OpenFOAM/lnInclude \
    -I$FOAM_SRC/OSspecific/POSIX/lnInclude \
    -I$FOAM_SRC/meshTools/lnInclude \
    -I$FOAM_SRC/sampling/lnInclude \
    -I$FOAM_SRC/TurbulenceModels/turbulenceModels/lnInclude \
    -I$FOAM_SRC/TurbulenceModels/incompressible/lnInclude \
    -I$FOAM_SRC/transportModels \
    -I$FOAM_SRC/transportModels/incompressible/singlePhaseTransportModel \
    -I$FOAM_SRC/dynamicMesh/lnInclude \
    -I$FOAM_SRC/dynamicFvMesh/lnInclude \
    -I$ROCM_PATH/include \
    -I$ROCM_PATH/include/hip \
    -I$ROCM_PATH/include/rocsparse \
    -I$ROCM_PATH/include/rocblas \
    -c hipSIMPLE.C \
    -o Make/$WM_OPTIONS/hipSIMPLE.o

if [ $? -ne 0 ]; then
    echo -e "${RED}✗ Compilation of hipSIMPLE.C failed${NC}"
    exit 1
fi
echo -e "${GREEN}✓ hipSIMPLE.o created${NC}"

echo ""
echo "Linking simpleHIPFoam..."

# Link executable
g++ -std=c++14 \
    -O3 \
    Make/$WM_OPTIONS/simpleHIPFoam.o \
    Make/$WM_OPTIONS/hipSIMPLE.o \
    -L$FOAM_LIBBIN \
    -L$FOAM_LIBBIN/dummy \
    -lfiniteVolume \
    -lfvOptions \
    -lmeshTools \
    -lsampling \
    -lturbulenceModels \
    -lincompressibleTurbulenceModels \
    -lincompressibleTransportModels \
    -ldynamicMesh \
    -ldynamicFvMesh \
    -lOpenFOAM \
    -ldl \
    -lm \
    -L$ROCM_PATH/lib \
    -lamdhip64 \
    -lrocsparse \
    -lrocblas \
    -Wl,-rpath,$FOAM_LIBBIN \
    -Wl,-rpath,$FOAM_LIBBIN/dummy \
    -Wl,-rpath,$ROCM_PATH/lib \
    -o $FOAM_USER_APPBIN/simpleHIPFoam

if [ $? -ne 0 ]; then
    echo -e "${RED}✗ Linking failed${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}=========================================="
echo "  ✓✓✓ BUILD SUCCESS ✓✓✓"
echo -e "==========================================${NC}"
echo ""
echo "Executable created:"
ls -lh "$FOAM_USER_APPBIN/simpleHIPFoam"
echo ""
echo "Test it:"
echo "  $FOAM_USER_APPBIN/simpleHIPFoam -help"
echo ""
echo "Add to PATH for convenience:"
echo "  export PATH=$FOAM_USER_APPBIN:\$PATH"