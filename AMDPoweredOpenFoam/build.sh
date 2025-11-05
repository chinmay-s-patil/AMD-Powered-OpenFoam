#!/bin/bash
# Build simpleHIPFoam - Run with: bash build.sh

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}=========================================="
echo "  Building simpleHIPFoam"
echo -e "==========================================${NC}\n"

# Check if already in OpenFOAM environment
if [ -z "$WM_PROJECT_DIR" ]; then
    echo -e "${YELLOW}OpenFOAM environment not loaded.${NC}"
    echo ""
    echo "Please run these commands first:"
    echo ""
    echo -e "${CYAN}  source /usr/lib/openfoam/openfoam2412/etc/bashrc"
    echo -e "  export ROCM_PATH=/opt/rocm"
    echo -e "  export PATH=\$ROCM_PATH/bin:\$PATH"
    echo -e "  export LD_LIBRARY_PATH=\$ROCM_PATH/lib:\$LD_LIBRARY_PATH"
    echo -e "  bash build.sh${NC}"
    echo ""
    exit 1
fi

echo -e "${GREEN}✓ OpenFOAM v$WM_PROJECT_VERSION loaded${NC}"
echo "  WM_PROJECT_DIR: $WM_PROJECT_DIR"
echo "  FOAM_SRC: $FOAM_SRC"

# Check ROCm
echo ""
echo -e "${BLUE}Checking ROCm/HIP...${NC}"
if command -v hipcc &> /dev/null; then
    echo -e "${GREEN}✓ hipcc found: $(which hipcc)${NC}"
    hipcc --version | head -1
else
    echo -e "${RED}✗ hipcc not found!${NC}"
    echo ""
    echo "Setup ROCm:"
    echo "  export ROCM_PATH=/opt/rocm"
    echo "  export PATH=\$ROCM_PATH/bin:\$PATH"
    echo "  export LD_LIBRARY_PATH=\$ROCM_PATH/lib:\$LD_LIBRARY_PATH"
    exit 1
fi

# Check GPU
echo ""
if command -v rocm-smi &> /dev/null; then
    echo -e "${BLUE}GPU Info:${NC}"
    rocm-smi --showproductname 2>/dev/null | grep -E "Card series|Card model" | head -1 || echo "  GPU detected"
fi

# Navigate to solver directory
echo ""
echo -e "${BLUE}Building simpleHIPFoam...${NC}"
echo ""

cd applications/solvers/simpleHIPFoam || {
    echo -e "${RED}ERROR: Cannot find applications/solvers/simpleHIPFoam${NC}"
    exit 1
}

# Clean previous build
echo "Cleaning old build artifacts..."
wclean 2>/dev/null || rm -rf Make/linux64* || true

# Build
echo ""
echo "Running wmake..."
echo ""

wmake 2>&1 | tee ../../../build.log

BUILD_STATUS=${PIPESTATUS[0]}

echo ""
if [ $BUILD_STATUS -eq 0 ]; then
    echo -e "${GREEN}=========================================="
    echo "  ✓✓✓ BUILD SUCCESSFUL! ✓✓✓"
    echo -e "==========================================${NC}"
    echo ""
    
    if [ -f "$FOAM_USER_APPBIN/simpleHIPFoam" ]; then
        echo "Executable created:"
        ls -lh "$FOAM_USER_APPBIN/simpleHIPFoam"
        echo ""
        echo -e "${CYAN}Test it:${NC}"
        echo "  simpleHIPFoam -help"
        echo ""
        echo -e "${CYAN}Next steps:${NC}"
        echo "  1. cd /path/to/your/openfoam/case"
        echo "  2. Add GPU settings to system/fvSolution"
        echo "  3. Run: simpleHIPFoam"
        echo ""
        echo "See Quickstart.md for details"
    else
        echo -e "${YELLOW}Warning: Build succeeded but executable not found${NC}"
        echo "Expected: $FOAM_USER_APPBIN/simpleHIPFoam"
    fi
else
    echo -e "${RED}=========================================="
    echo "  ✗✗✗ BUILD FAILED ✗✗✗"
    echo -e "==========================================${NC}"
    echo ""
    echo "Check the error messages above."
    echo "Full log saved to: build.log"
    exit 1
fi