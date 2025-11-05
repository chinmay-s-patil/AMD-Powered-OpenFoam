#!/bin/bash
# Build simpleHIPFoam with proper environment setup

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}=========================================="
echo "  Building simpleHIPFoam"
echo -e "==========================================${NC}\n"

# 1. Source OpenFOAM environment
echo -e "${BLUE}[1/4] Loading OpenFOAM environment...${NC}"
source /usr/lib/openfoam/openfoam2412/etc/bashrc

echo -e "${GREEN}✓ OpenFOAM v$WM_PROJECT_VERSION loaded${NC}"
echo "  FOAM_SRC: $FOAM_SRC"
echo "  FOAM_APPBIN: $FOAM_APPBIN"

# 2. Setup ROCm environment
echo ""
echo -e "${BLUE}[2/4] Loading ROCm environment...${NC}"
export ROCM_PATH=${ROCM_PATH:-/opt/rocm}
export PATH=$ROCM_PATH/bin:$PATH
export LD_LIBRARY_PATH=$ROCM_PATH/lib:$LD_LIBRARY_PATH

if command -v hipcc &> /dev/null; then
    HIP_VERSION=$(hipcc --version 2>&1 | head -n 1)
    echo -e "${GREEN}✓ ROCm/HIP loaded${NC}"
    echo "  hipcc: $(which hipcc)"
    echo "  Version: $HIP_VERSION"
else
    echo -e "${RED}✗ hipcc not found!${NC}"
    exit 1
fi

# 3. Check GPU
echo ""
echo -e "${BLUE}[3/4] Checking GPU...${NC}"
if command -v rocm-smi &> /dev/null; then
    GPU_INFO=$(rocm-smi --showproductname 2>/dev/null | grep -E "Card series|Card model" | head -1)
    if [ -n "$GPU_INFO" ]; then
        echo -e "${GREEN}✓ GPU detected${NC}"
        echo "  $GPU_INFO"
    else
        echo -e "${YELLOW}⚠ rocm-smi found but no GPU info${NC}"
    fi
else
    echo -e "${YELLOW}⚠ rocm-smi not available${NC}"
fi

# 4. Build simpleHIPFoam
echo ""
echo -e "${BLUE}[4/4] Building simpleHIPFoam...${NC}"
echo ""

cd applications/solvers/simpleHIPFoam

# Clean old build
echo "Cleaning previous build..."
wclean 2>/dev/null || rm -rf Make/linux64* || true

echo ""
echo "Building with wmake..."
echo ""

# Set compiler to hipcc
export WM_CC=hipcc
export WM_CXX=hipcc

# Build
if wmake 2>&1 | tee ../../../build.log; then
    echo ""
    echo -e "${GREEN}=========================================="
    echo "  ✓ Build Successful!"
    echo -e "==========================================${NC}"
    echo ""
    echo "Executable: $FOAM_USER_APPBIN/simpleHIPFoam"
    
    # Check if executable exists
    if [ -f "$FOAM_USER_APPBIN/simpleHIPFoam" ]; then
        echo ""
        ls -lh "$FOAM_USER_APPBIN/simpleHIPFoam"
        echo ""
        echo -e "${CYAN}Test it:${NC}"
        echo "  simpleHIPFoam -help"
    fi
else
    echo ""
    echo -e "${RED}=========================================="
    echo "  ✗ Build Failed!"
    echo -e "==========================================${NC}"
    echo ""
    echo "Check build.log for details"
    exit 1
fi