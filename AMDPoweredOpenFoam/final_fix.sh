#!/bin/bash
# Final fix - correct both Make/files and Make/options

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${CYAN}=========================================="
echo "  Final Fix for wmake"
echo -e "==========================================${NC}"
echo ""

cd applications/solvers/simpleHIPFoam

echo -e "${BLUE}Step 1: Fixing Make/files${NC}"
# The problem: hipSIMPLE.C is in hipSolver/ subdirectory
cat > Make/files << 'EOF'
simpleHIPFoam.C
hipSolver/hipSIMPLE.C

EXE = $(FOAM_USER_APPBIN)/simpleHIPFoam
EOF

echo "✓ Make/files updated with correct path"
cat Make/files
echo ""

echo -e "${BLUE}Step 2: Fixing Make/options - using FOAM_SRC${NC}"
# Use FOAM_SRC which wmake DOES expand, not LIB_SRC
cat > Make/options << 'EOF'
EXE_INC = \
    -I$(FOAM_SRC)/finiteVolume/lnInclude \
    -I$(FOAM_SRC)/OpenFOAM/lnInclude \
    -I$(FOAM_SRC)/OSspecific/POSIX/lnInclude \
    -I$(FOAM_SRC)/meshTools/lnInclude \
    -I$(FOAM_SRC)/sampling/lnInclude \
    -I$(FOAM_SRC)/TurbulenceModels/turbulenceModels/lnInclude \
    -I$(FOAM_SRC)/TurbulenceModels/incompressible/lnInclude \
    -I$(FOAM_SRC)/transportModels \
    -I$(FOAM_SRC)/transportModels/incompressible/singlePhaseTransportModel \
    -I$(FOAM_SRC)/dynamicMesh/lnInclude \
    -I$(FOAM_SRC)/dynamicFvMesh/lnInclude \
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

echo "✓ Make/options updated with FOAM_SRC variable"
echo ""

echo -e "${BLUE}Step 3: Verify FOAM_SRC is set${NC}"
if [ -z "$FOAM_SRC" ]; then
    echo -e "${YELLOW}⚠ FOAM_SRC not set, setting it now...${NC}"
    export FOAM_SRC="/usr/lib/openfoam/openfoam2406/src"
fi
echo "FOAM_SRC = $FOAM_SRC"
echo ""

echo -e "${BLUE}Step 4: Clean and rebuild${NC}"
wclean
echo ""

echo -e "${BLUE}Step 5: Build with wmake${NC}"
echo ""
wmake 2>&1 | tee ../../../build_final.log

if [ ${PIPESTATUS[0]} -eq 0 ]; then
    echo ""
    echo -e "${GREEN}=========================================="
    echo "  ✓✓✓ BUILD SUCCESSFUL! ✓✓✓"
    echo -e "==========================================${NC}"
    echo ""
    
    FOAM_USER_APPBIN="$HOME/OpenFOAM/$(whoami)-v2406/platforms/linux64GccDPInt32Opt/bin"
    if [ -f "$FOAM_USER_APPBIN/simpleHIPFoam" ]; then
        echo -e "${GREEN}Executable created:${NC}"
        ls -lh "$FOAM_USER_APPBIN/simpleHIPFoam"
        echo ""
        echo -e "${CYAN}Test it:${NC}"
        echo "  $FOAM_USER_APPBIN/simpleHIPFoam -help"
    fi
else
    echo ""
    echo -e "${RED}=========================================="
    echo "  ✗✗✗ BUILD FAILED ✗✗✗"
    echo -e "==========================================${NC}"
    echo ""
    
    echo "Compiler command that was used:"
    grep "^g++" ../../../build_final.log | head -1
    echo ""
    
    echo "Checking preprocessed options:"
    if [ -f "Make/linux64GccDPInt32Opt/options" ]; then
        head -20 Make/linux64GccDPInt32Opt/options
    fi
    echo ""
    
    echo "Last 30 lines:"
    tail -30 ../../../build_final.log
    exit 1
fi