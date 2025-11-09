#!/bin/bash
# Complete build script for simpleHIPFoam with OpenFOAM v2406
# This is a standalone script - you can delete all other .sh files after using this
# Usage: ./build_simpleHIPFoam.sh

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}=========================================="
echo "  simpleHIPFoam Build Script"
echo "  OpenFOAM v2406 + ROCm/HIP"
echo -e "==========================================${NC}\n"

# ============================================
# STEP 1: Locate OpenFOAM v2406
# ============================================
echo -e "${BLUE}[1/6] Locating OpenFOAM v2406...${NC}"

OPENFOAM_LOCATIONS=(
    "$HOME/OpenFOAM/OpenFOAM-v2406"
    "/usr/lib/openfoam/openfoam2406"
    "/opt/openfoam2406"
)

OPENFOAM_DIR=""
for loc in "${OPENFOAM_LOCATIONS[@]}"; do
    if [ -d "$loc" ] && [ -f "$loc/etc/bashrc" ]; then
        OPENFOAM_DIR="$loc"
        echo -e "${GREEN}✓ Found: $loc${NC}"
        break
    fi
done

if [ -z "$OPENFOAM_DIR" ]; then
    echo -e "${RED}✗ OpenFOAM v2406 not found!${NC}"
    echo ""
    echo "Searched:"
    for loc in "${OPENFOAM_LOCATIONS[@]}"; do
        echo "  - $loc"
    done
    echo ""
    echo "Please install OpenFOAM v2406 first:"
    echo "  https://www.openfoam.com/download"
    exit 1
fi

# ============================================
# STEP 2: Setup OpenFOAM Environment
# ============================================
echo ""
echo -e "${BLUE}[2/6] Setting up OpenFOAM environment...${NC}"

# Try to extract environment without hanging on bashrc
ENV_VARS=$(timeout 10s bash -c "
    source '$OPENFOAM_DIR/etc/bashrc' 2>/dev/null
    echo WM_PROJECT_DIR=\$WM_PROJECT_DIR
    echo WM_PROJECT_VERSION=\$WM_PROJECT_VERSION
    echo FOAM_SRC=\$FOAM_SRC
    echo FOAM_APPBIN=\$FOAM_APPBIN
    echo FOAM_USER_APPBIN=\$FOAM_USER_APPBIN
    echo FOAM_USER_LIBBIN=\$FOAM_USER_LIBBIN
    echo FOAM_LIBBIN=\$FOAM_LIBBIN
    echo WM_DIR=\$WM_DIR
    echo WM_OPTIONS=\$WM_OPTIONS
    echo LIB_SRC=\$LIB_SRC
" 2>/dev/null) || {
    echo -e "${YELLOW}⚠ bashrc timeout, using manual setup...${NC}"
    ENV_VARS=""
}

if [ -n "$ENV_VARS" ]; then
    # Load extracted variables
    eval "$ENV_VARS"
    export $(echo "$ENV_VARS" | cut -d= -f1)
    echo -e "${GREEN}✓ Environment loaded from bashrc${NC}"
else
    # Manual fallback
    export WM_PROJECT_DIR="$OPENFOAM_DIR"
    export WM_PROJECT_VERSION="v2406"
    export FOAM_SRC="$WM_PROJECT_DIR/src"
    export WM_OPTIONS="linux64GccDPInt32Opt"
    export FOAM_APPBIN="$WM_PROJECT_DIR/platforms/$WM_OPTIONS/bin"
    export FOAM_LIBBIN="$WM_PROJECT_DIR/platforms/$WM_OPTIONS/lib"
    export FOAM_USER_APPBIN="$HOME/OpenFOAM/$(whoami)-v2406/platforms/$WM_OPTIONS/bin"
    export FOAM_USER_LIBBIN="$HOME/OpenFOAM/$(whoami)-v2406/platforms/$WM_OPTIONS/lib"
    export WM_DIR="$WM_PROJECT_DIR/wmake"
    export LIB_SRC="$FOAM_SRC"
    echo -e "${GREEN}✓ Manual environment setup${NC}"
fi

# Add to PATH
export PATH="$FOAM_APPBIN:$WM_DIR:$PATH"
export LD_LIBRARY_PATH="$FOAM_LIBBIN:$LD_LIBRARY_PATH"

# Verify critical variables
if [ -z "$WM_PROJECT_DIR" ] || [ -z "$FOAM_SRC" ]; then
    echo -e "${RED}✗ Critical environment variables not set!${NC}"
    exit 1
fi

echo "  WM_PROJECT_DIR: $WM_PROJECT_DIR"
echo "  FOAM_SRC: $FOAM_SRC"
echo "  WM_OPTIONS: $WM_OPTIONS"

# Create user directories
mkdir -p "$FOAM_USER_APPBIN" "$FOAM_USER_LIBBIN" 2>/dev/null || true

# ============================================
# STEP 3: Verify OpenFOAM Headers
# ============================================
echo ""
echo -e "${BLUE}[3/6] Verifying OpenFOAM headers...${NC}"

CRITICAL_HEADERS=(
    "$FOAM_SRC/finiteVolume/lnInclude/fvCFD.H"
    "$FOAM_SRC/OpenFOAM/lnInclude/lduMatrix.H"
    "$FOAM_SRC/finiteVolume/lnInclude/fvMesh.H"
)

MISSING_COUNT=0
for header in "${CRITICAL_HEADERS[@]}"; do
    if [ -f "$header" ]; then
        echo -e "  ${GREEN}✓${NC} $(basename $header)"
    else
        echo -e "  ${RED}✗${NC} $(basename $header)"
        ((MISSING_COUNT++))
    fi
done

if [ $MISSING_COUNT -gt 0 ]; then
    echo ""
    echo -e "${YELLOW}⚠ Missing $MISSING_COUNT critical headers${NC}"
    echo "  Attempting to rebuild lnInclude directories..."
    
    cd "$FOAM_SRC"
    
    # Try to rebuild lnInclude for critical directories
    for dir in OpenFOAM finiteVolume meshTools; do
        if [ -d "$dir" ]; then
            echo "    Rebuilding: $dir/lnInclude"
            $WM_DIR/wmakeLnInclude "$dir" 2>/dev/null || {
                mkdir -p "$dir/lnInclude"
                find "$dir" -maxdepth 2 -name "*.H" -exec ln -sf {} "$dir/lnInclude/" \; 2>/dev/null
            }
        fi
    done
    
    # Re-verify
    STILL_MISSING=0
    for header in "${CRITICAL_HEADERS[@]}"; do
        [ ! -f "$header" ] && ((STILL_MISSING++))
    done
    
    if [ $STILL_MISSING -gt 0 ]; then
        echo ""
        echo -e "${RED}✗ Still missing headers after rebuild!${NC}"
        echo "  Your OpenFOAM installation may be incomplete."
        exit 1
    fi
    
    echo -e "${GREEN}✓ Headers rebuilt successfully${NC}"
fi

# ============================================
# STEP 4: Setup ROCm/HIP
# ============================================
echo ""
echo -e "${BLUE}[4/6] Setting up ROCm/HIP...${NC}"

export ROCM_PATH=${ROCM_PATH:-/opt/rocm}
export PATH=$ROCM_PATH/bin:$PATH
export LD_LIBRARY_PATH=$ROCM_PATH/lib:$LD_LIBRARY_PATH

if ! command -v hipcc &> /dev/null; then
    echo -e "${RED}✗ hipcc not found!${NC}"
    echo ""
    echo "Please install ROCm first:"
    echo "  https://rocm.docs.amd.com/en/latest/deploy/linux/quick_start.html"
    exit 1
fi

HIP_VERSION=$(hipcc --version 2>&1 | head -1)
echo -e "${GREEN}✓ HIP found${NC}"
echo "  Location: $(which hipcc)"
echo "  Version: $HIP_VERSION"

# Check GPU
if command -v rocm-smi &> /dev/null; then
    GPU_INFO=$(rocm-smi --showproductname 2>/dev/null | grep -E "Card series|Card model" | head -1 | cut -d: -f2 | xargs)
    if [ -n "$GPU_INFO" ]; then
        echo "  GPU: $GPU_INFO"
    fi
fi

# ============================================
# STEP 5: Verify Project Structure
# ============================================
echo ""
echo -e "${BLUE}[5/6] Verifying project files...${NC}"

if [ ! -f "applications/solvers/simpleHIPFoam/simpleHIPFoam.C" ]; then
    echo -e "${RED}✗ simpleHIPFoam.C not found!${NC}"
    echo "  Are you in the AMDPoweredOpenFoam directory?"
    exit 1
fi

if [ ! -f "applications/solvers/simpleHIPFoam/hipSolver/hipSIMPLE.C" ]; then
    echo -e "${RED}✗ hipSIMPLE.C not found!${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Source files found${NC}"

# Create/update Make/options with correct paths
echo "  Updating Make/options..."
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

echo -e "${GREEN}✓ Make/options updated${NC}"

# ============================================
# STEP 6: Build
# ============================================
echo ""
echo -e "${BLUE}[6/6] Building simpleHIPFoam...${NC}"
echo ""

cd applications/solvers/simpleHIPFoam

# Clean previous build
echo "Cleaning previous build..."
wclean 2>/dev/null || rm -rf Make/linux64* || true

echo ""
echo "Building with wmake..."
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
        
        # Create convenience wrapper script
        cat > run_simpleHIPFoam.sh << EOFRUN
#!/bin/bash
# Wrapper to run simpleHIPFoam with proper environment

export WM_PROJECT_DIR="$WM_PROJECT_DIR"
export FOAM_USER_APPBIN="$FOAM_USER_APPBIN"
export PATH="$FOAM_APPBIN:\$PATH"
export LD_LIBRARY_PATH="$FOAM_LIBBIN:\$LD_LIBRARY_PATH"
export ROCM_PATH=/opt/rocm
export PATH=\$ROCM_PATH/bin:\$PATH
export LD_LIBRARY_PATH=\$ROCM_PATH/lib:\$LD_LIBRARY_PATH

$FOAM_USER_APPBIN/simpleHIPFoam "\$@"
EOFRUN
        chmod +x run_simpleHIPFoam.sh
        
        echo -e "${CYAN}Created wrapper script: run_simpleHIPFoam.sh${NC}"
        echo "  Use it to run simpleHIPFoam without manually loading environment"
        echo ""
        echo -e "${CYAN}Next steps:${NC}"
        echo "  1. Copy run_simpleHIPFoam.sh to your case directory"
        echo "  2. Add GPU settings to system/fvSolution (see Quickstart.md)"
        echo "  3. Run: ./run_simpleHIPFoam.sh"
        echo ""
        echo -e "${CYAN}Or add to ~/.bashrc for permanent setup:${NC}"
        echo "  export PATH=$FOAM_USER_APPBIN:\$PATH"
        echo "  export PATH=/opt/rocm/bin:\$PATH"
        echo "  export LD_LIBRARY_PATH=/opt/rocm/lib:\$LD_LIBRARY_PATH"
        
    else
        echo -e "${YELLOW}⚠ Executable not found at expected location${NC}"
        echo "  Expected: $FOAM_USER_APPBIN/simpleHIPFoam"
        echo ""
        echo "Searching for it..."
        find "$HOME/OpenFOAM" -name "simpleHIPFoam" -type f 2>/dev/null | head -3
    fi
else
    echo -e "${RED}=========================================="
    echo "  ✗✗✗ BUILD FAILED ✗✗✗"
    echo -e "==========================================${NC}"
    echo ""
    
    # Diagnose common errors
    if grep -q "fvCFD.H: No such file" build.log; then
        echo -e "${YELLOW}Error: Cannot find fvCFD.H${NC}"
        echo "Your OpenFOAM development files may be incomplete."
    elif grep -q "hipcc.*not found" build.log; then
        echo -e "${YELLOW}Error: hipcc not properly configured${NC}"
    else
        echo "Last 30 lines of build.log:"
        tail -30 build.log
    fi
    
    echo ""
    echo "Full log saved to: build.log"
    exit 1
fi

echo ""
echo -e "${GREEN}Done! You can now delete all other .sh build scripts.${NC}"
echo -e "${GREEN}Keep this script (build_simpleHIPFoam.sh) for rebuilding.${NC}"