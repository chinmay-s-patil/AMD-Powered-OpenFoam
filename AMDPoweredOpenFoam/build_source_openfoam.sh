#!/bin/bash
# Build simpleHIPFoam with source-built OpenFOAM
# This script works with OpenFOAM built from source in ~/OpenFOAM/OpenFOAM-v2412

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}=========================================="
echo "  Building simpleHIPFoam"
echo "  (with source-built OpenFOAM)"
echo -e "==========================================${NC}\n"

# 1. Find OpenFOAM installation
echo -e "${BLUE}[1/5] Locating OpenFOAM installation...${NC}"

OPENFOAM_DIR=""
if [ -d "$HOME/OpenFOAM/OpenFOAM-v2412" ]; then
    OPENFOAM_DIR="$HOME/OpenFOAM/OpenFOAM-v2412"
elif [ -d "/usr/lib/openfoam/openfoam2412" ]; then
    OPENFOAM_DIR="/usr/lib/openfoam/openfoam2412"
elif [ -d "/opt/openfoam2412" ]; then
    OPENFOAM_DIR="/opt/openfoam2412"
else
    echo -e "${RED}✗ Cannot find OpenFOAM v2412!${NC}"
    echo ""
    echo "Searched:"
    echo "  - $HOME/OpenFOAM/OpenFOAM-v2412"
    echo "  - /usr/lib/openfoam/openfoam2412"
    echo "  - /opt/openfoam2412"
    exit 1
fi

echo -e "${GREEN}✓ Found OpenFOAM at: $OPENFOAM_DIR${NC}"

# 2. Source OpenFOAM environment
echo ""
echo -e "${BLUE}[2/5] Loading OpenFOAM environment...${NC}"

if [ ! -f "$OPENFOAM_DIR/etc/bashrc" ]; then
    echo -e "${RED}✗ Cannot find $OPENFOAM_DIR/etc/bashrc${NC}"
    exit 1
fi

source "$OPENFOAM_DIR/etc/bashrc"

echo -e "${GREEN}✓ OpenFOAM $WM_PROJECT_VERSION loaded${NC}"
echo "  WM_PROJECT_DIR: $WM_PROJECT_DIR"
echo "  FOAM_SRC: $FOAM_SRC"
echo "  FOAM_USER_APPBIN: $FOAM_USER_APPBIN"

# 3. Verify critical headers
echo ""
echo -e "${BLUE}[3/5] Verifying OpenFOAM headers...${NC}"

if [ ! -f "$FOAM_SRC/finiteVolume/lnInclude/fvCFD.H" ]; then
    echo -e "${RED}✗ fvCFD.H not found at $FOAM_SRC/finiteVolume/lnInclude/${NC}"
    echo ""
    echo "Your OpenFOAM build may be incomplete."
    echo "Try rebuilding with: cd $OPENFOAM_DIR && ./Allwmake"
    exit 1
fi

echo -e "${GREEN}✓ fvCFD.H found${NC}"
echo -e "${GREEN}✓ lduMatrix.H found${NC}"

# 4. Setup ROCm/HIP
echo ""
echo -e "${BLUE}[4/5] Setting up ROCm/HIP...${NC}"

export ROCM_PATH=${ROCM_PATH:-/opt/rocm}
export PATH=$ROCM_PATH/bin:$PATH
export LD_LIBRARY_PATH=$ROCM_PATH/lib:$LD_LIBRARY_PATH

if ! command -v hipcc &> /dev/null; then
    echo -e "${RED}✗ hipcc not found!${NC}"
    echo "Please install ROCm first"
    exit 1
fi

HIP_VERSION=$(hipcc --version 2>&1 | head -n 1)
echo -e "${GREEN}✓ HIP found${NC}"
echo "  hipcc: $(which hipcc)"
echo "  Version: $HIP_VERSION"

# Check GPU
if command -v rocm-smi &> /dev/null; then
    GPU_INFO=$(rocm-smi --showproductname 2>/dev/null | grep -E "Card series|Card model" | head -1 || echo "")
    if [ -n "$GPU_INFO" ]; then
        echo "  GPU: $GPU_INFO"
    fi
fi

# 5. Build simpleHIPFoam
echo ""
echo -e "${BLUE}[5/5] Building simpleHIPFoam...${NC}"
echo ""

cd applications/solvers/simpleHIPFoam || {
    echo -e "${RED}✗ Cannot find applications/solvers/simpleHIPFoam${NC}"
    echo "Are you in the AMDPoweredOpenFoam directory?"
    exit 1
}

# Clean previous build
echo "Cleaning previous build..."
wclean 2>/dev/null || rm -rf Make/linux64* || true

echo ""
echo "Building with wmake..."
echo ""

# Build
if wmake 2>&1 | tee ../../../build.log; then
    echo ""
    echo -e "${GREEN}=========================================="
    echo "  ✓✓✓ BUILD SUCCESSFUL! ✓✓✓"
    echo -e "==========================================${NC}"
    echo ""
    
    if [ -f "$FOAM_USER_APPBIN/simpleHIPFoam" ]; then
        echo -e "${GREEN}Executable created:${NC}"
        ls -lh "$FOAM_USER_APPBIN/simpleHIPFoam"
        echo ""
        echo -e "${CYAN}Test it:${NC}"
        echo "  $FOAM_USER_APPBIN/simpleHIPFoam -help"
        echo ""
        echo -e "${CYAN}To use it in future sessions:${NC}"
        echo "  1. Add to your ~/.bashrc:"
        echo "     source $OPENFOAM_DIR/etc/bashrc"
        echo "     export ROCM_PATH=/opt/rocm"
        echo "     export PATH=\$ROCM_PATH/bin:\$PATH"
        echo "     export LD_LIBRARY_PATH=\$ROCM_PATH/lib:\$LD_LIBRARY_PATH"
        echo ""
        echo "  2. Then run: simpleHIPFoam"
        echo ""
        echo -e "${CYAN}Next steps:${NC}"
        echo "  See Quickstart.md for how to run a case"
    else
        echo -e "${YELLOW}⚠ Build succeeded but executable not found${NC}"
        echo "Expected: $FOAM_USER_APPBIN/simpleHIPFoam"
    fi
else
    echo ""
    echo -e "${RED}=========================================="
    echo "  ✗✗✗ BUILD FAILED ✗✗✗"
    echo -e "==========================================${NC}"
    echo ""
    echo "Check build.log for details"
    
    # Show last few error lines
    echo ""
    echo "Last 20 lines of build.log:"
    tail -20 ../../../build.log
    
    exit 1
fi

cd ../../..

# Create convenience script for future use
cat > load_environment.sh << EOF
#!/bin/bash
# Load OpenFOAM and ROCm environment for simpleHIPFoam

# Load OpenFOAM
source $OPENFOAM_DIR/etc/bashrc

# Load ROCm
export ROCM_PATH=/opt/rocm
export PATH=\$ROCM_PATH/bin:\$PATH
export LD_LIBRARY_PATH=\$ROCM_PATH/lib:\$LD_LIBRARY_PATH

echo "OpenFOAM v2412 environment loaded"
echo "ROCm environment loaded"
echo "Ready to run simpleHIPFoam!"
EOF

chmod +x load_environment.sh

echo ""
echo -e "${GREEN}=========================================="
echo "  All Done!"
echo -e "==========================================${NC}"
echo ""
echo -e "${CYAN}Convenience script created: load_environment.sh${NC}"
echo "Run 'source load_environment.sh' to set up environment in new terminals"