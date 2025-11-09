#!/bin/bash
# Ultimate fix - check OpenFOAM's own solvers to see correct format

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}=========================================="
echo "  Ultimate Fix - Copy from working solver"
echo -e "==========================================${NC}"
echo ""

# First, check how simpleFoam does it
echo -e "${BLUE}Checking how OpenFOAM's simpleFoam is configured:${NC}"

SIMPLEFOAM_DIR="/usr/lib/openfoam/openfoam2406/applications/solvers/incompressible/simpleFoam"
if [ -f "$SIMPLEFOAM_DIR/Make/options" ]; then
    echo "Found simpleFoam Make/options:"
    cat "$SIMPLEFOAM_DIR/Make/options"
    echo ""
else
    echo "simpleFoam not found at expected location"
fi

cd applications/solvers/simpleHIPFoam

echo -e "${BLUE}Creating Make/options based on simpleFoam:${NC}"

# Create options file matching OpenFOAM's format EXACTLY
cat > Make/options << 'EOFOPT'
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
EOFOPT

echo "✓ Make/options created"
echo ""

echo -e "${BLUE}Creating Make/files:${NC}"
cat > Make/files << 'EOFFILES'
simpleHIPFoam.C
hipSolver/hipSIMPLE.C

EXE = $(FOAM_USER_APPBIN)/simpleHIPFoam
EOFFILES

echo "✓ Make/files created"
echo ""

echo -e "${BLUE}Removing c++FLAGS override (letting wmake handle it):${NC}"
# The issue might be that c++FLAGS is interfering
echo "Previous c++FLAGS override removed - wmake will use defaults + our additions"
echo ""

echo -e "${BLUE}Clean build:${NC}"
wclean
rm -rf Make/linux64GccDPInt32Opt
echo ""

# Source OpenFOAM properly
echo -e "${BLUE}Sourcing OpenFOAM environment:${NC}"
if [ -z "$WM_PROJECT_DIR" ]; then
    source /usr/lib/openfoam/openfoam2406/etc/bashrc
fi

echo "Environment variables:"
echo "  WM_PROJECT_DIR: $WM_PROJECT_DIR"  
echo "  FOAM_SRC: $FOAM_SRC"
echo "  LIB_SRC: $LIB_SRC"
echo "  WM_OPTIONS: $WM_OPTIONS"
echo ""

# Set compiler to use hipcc
echo -e "${BLUE}Setting compiler to hipcc:${NC}"
export WM_CC=hipcc
export WM_CXX=hipcc
export WM_CXXFLAGS="-std=c++14 -O3 -fPIC -D__HIP_PLATFORM_AMD__"
echo "  WM_CXX: $WM_CXX"
echo ""

echo -e "${BLUE}Building:${NC}"
echo ""
wmake 2>&1 | tee ../../../build_ultimate.log

BUILD_EXIT=${PIPESTATUS[0]}

if [ $BUILD_EXIT -eq 0 ]; then
    echo ""
    echo -e "${GREEN}=========================================="
    echo "  ✓✓✓ BUILD SUCCESSFUL! ✓✓✓"
    echo -e "==========================================${NC}"
    echo ""
    
    if [ -f "$FOAM_USER_APPBIN/simpleHIPFoam" ]; then
        echo -e "${GREEN}Executable:${NC}"
        ls -lh "$FOAM_USER_APPBIN/simpleHIPFoam"
        echo ""
        echo -e "${CYAN}Test:${NC}"
        echo "  simpleHIPFoam -help"
    fi
else
    echo ""
    echo -e "${RED}=========================================="
    echo "  ✗✗✗ BUILD STILL FAILING ✗✗✗"
    echo -e "==========================================${NC}"
    echo ""
    
    echo "Actual compiler command:"
    grep "^g++\|^hipcc" ../../../build_ultimate.log | head -3
    echo ""
    
    echo "Preprocessed options:"
    if [ -f "Make/linux64GccDPInt32Opt/options" ]; then
        cat Make/linux64GccDPInt32Opt/options | grep -A5 "EXE_INC"
    fi
    echo ""
    
    echo -e "${YELLOW}Let me try one more thing - direct compilation:${NC}"
    echo ""
    
    # Try compiling directly with all the right flags
    hipcc -std=c++14 \
        -I$LIB_SRC/finiteVolume/lnInclude \
        -I$LIB_SRC/OpenFOAM/lnInclude \
        -I$LIB_SRC/OSspecific/POSIX/lnInclude \
        -I$LIB_SRC/meshTools/lnInclude \
        -O3 -fPIC -D__HIP_PLATFORM_AMD__ \
        -DFOAM_LABEL_SIZE=32 \
        -DWM_DP \
        -c simpleHIPFoam.C -o /tmp/test.o 2>&1 | head -20
    
    if [ $? -eq 0 ]; then
        echo ""
        echo -e "${CYAN}✓ Direct hipcc compilation WORKS!${NC}"
        echo "  The issue is definitely with wmake not passing includes"
    fi
fi