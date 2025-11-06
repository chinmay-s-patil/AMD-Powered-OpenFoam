#!/bin/bash
# Build simpleHIPFoam with source-built OpenFOAM
# This script properly handles environment setup without hanging

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

# 1. Setup OpenFOAM environment
echo -e "${BLUE}[1/4] Setting up OpenFOAM environment...${NC}"

OPENFOAM_DIR="$HOME/OpenFOAM/OpenFOAM-v2412"

if [ ! -d "$OPENFOAM_DIR" ]; then
    echo -e "${RED}✗ OpenFOAM not found at $OPENFOAM_DIR${NC}"
    exit 1
fi

# Source bashrc in a way that doesn't hang
export FOAM_INST_DIR="$HOME/OpenFOAM"
cd "$OPENFOAM_DIR" && source etc/bashrc > /dev/null 2>&1
cd - > /dev/null

if [ -z "$WM_PROJECT_DIR" ]; then
    echo -e "${RED}✗ Failed to load OpenFOAM environment${NC}"
    exit 1
fi

echo -e "${GREEN}✓ OpenFOAM $WM_PROJECT_VERSION loaded${NC}"
echo "  WM_PROJECT_DIR: $WM_PROJECT_DIR"
echo "  FOAM_APPBIN: $FOAM_APPBIN"
echo "  FOAM_USER_APPBIN: $FOAM_USER_APPBIN"

# Verify fvCFD.H exists
if [ ! -f "$FOAM_SRC/finiteVolume/lnInclude/fvCFD.H" ]; then
    echo -e "${RED}✗ fvCFD.H not found${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Critical headers verified${NC}"

# 2. Setup ROCm/HIP
echo ""
echo -e "${BLUE}[2/4] Setting up ROCm/HIP...${NC}"

export ROCM_PATH=${ROCM_PATH:-/opt/rocm}
export PATH=$ROCM_PATH/bin:$PATH
export LD_LIBRARY_PATH=$ROCM_PATH/lib:$LD_LIBRARY_PATH

if ! command -v hipcc &> /dev/null; then
    echo -e "${RED}✗ hipcc not found${NC}"
    echo "Please install ROCm first"
    exit 1
fi

HIP_VERSION=$(hipcc --version 2>&1 | head -n 1)
echo -e "${GREEN}✓ HIP found${NC}"
echo "  Location: $(which hipcc)"
echo "  Version: $HIP_VERSION"

# Check GPU
if command -v rocm-smi &> /dev/null; then
    GPU_INFO=$(rocm-smi --showproductname 2>/dev/null | grep -E "Card series|Card model" | head -1 || echo "AMD GPU")
    echo "  GPU: $GPU_INFO"
fi

# 3. Verify we're in the right directory
echo ""
echo -e "${BLUE}[3/4] Verifying project structure...${NC}"

if [ ! -f "applications/solvers/simpleHIPFoam/simpleHIPFoam.C" ]; then
    echo -e "${RED}✗ simpleHIPFoam source files not found${NC}"
    echo "Please run this script from the AMDPoweredOpenFoam directory"
    exit 1
fi

echo -e "${GREEN}✓ Project structure OK${NC}"

# Create user directories if needed
mkdir -p "$FOAM_USER_APPBIN" "$FOAM_USER_LIBBIN" 2>/dev/null || true

# 4. Build simpleHIPFoam
echo ""
echo -e "${BLUE}[4/4] Building simpleHIPFoam...${NC}"
echo ""

cd applications/solvers/simpleHIPFoam

# Clean previous build
echo "Cleaning previous build..."
wclean > /dev/null 2>&1 || rm -rf Make/linux64* || true

echo ""
echo "Compiling..."
echo ""

# Build and capture output
if wmake 2>&1 | tee ../../../build.log; then
    BUILD_SUCCESS=true
else
    BUILD_SUCCESS=false
fi

cd ../../..

echo ""
if [ "$BUILD_SUCCESS" = true ]; then
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
        
        # Create convenience script
        cat > run_simpleHIPFoam.sh << EOF
#!/bin/bash
# Convenience script to run simpleHIPFoam with proper environment

# Setup OpenFOAM environment
export FOAM_INST_DIR="$HOME/OpenFOAM"
cd "$OPENFOAM_DIR" && source etc/bashrc > /dev/null 2>&1
cd - > /dev/null

# Setup ROCm
export ROCM_PATH=/opt/rocm
export PATH=\$ROCM_PATH/bin:\$PATH
export LD_LIBRARY_PATH=\$ROCM_PATH/lib:\$LD_LIBRARY_PATH

# Run simpleHIPFoam with all arguments
simpleHIPFoam "\$@"
EOF
        chmod +x run_simpleHIPFoam.sh
        
        echo -e "${CYAN}Created convenience script: run_simpleHIPFoam.sh${NC}"
        echo "Use it to run simpleHIPFoam without manually loading environment"
        echo ""
        echo -e "${CYAN}For permanent setup, add to ~/.bashrc:${NC}"
        echo ""
        echo "  # OpenFOAM environment"
        echo "  export FOAM_INST_DIR=\$HOME/OpenFOAM"
        echo "  source \$HOME/OpenFOAM/OpenFOAM-v2412/etc/bashrc"
        echo ""
        echo "  # ROCm environment"
        echo "  export ROCM_PATH=/opt/rocm"
        echo "  export PATH=\$ROCM_PATH/bin:\$PATH"
        echo "  export LD_LIBRARY_PATH=\$ROCM_PATH/lib:\$LD_LIBRARY_PATH"
        echo ""
        echo -e "${CYAN}Next steps:${NC}"
        echo "  1. Copy a test case (see Quickstart.md)"
        echo "  2. Add GPU settings to system/fvSolution"
        echo "  3. Run: ./run_simpleHIPFoam.sh"
        
    else
        echo -e "${YELLOW}⚠ Build succeeded but executable not found at:${NC}"
        echo "  $FOAM_USER_APPBIN/simpleHIPFoam"
        echo ""
        echo "It may have been placed in:"
        echo "  $FOAM_APPBIN/simpleHIPFoam"
        find "$HOME/OpenFOAM" -name "simpleHIPFoam" -type f 2>/dev/null | head -5
    fi
else
    echo -e "${RED}=========================================="
    echo "  ✗✗✗ BUILD FAILED ✗✗✗"
    echo -e "==========================================${NC}"
    echo ""
    echo "Last 30 lines of build.log:"
    tail -30 build.log
    echo ""
    echo "Full log saved to: build.log"
    exit 1
fi

echo ""
echo -e "${GREEN}Done!${NC}"