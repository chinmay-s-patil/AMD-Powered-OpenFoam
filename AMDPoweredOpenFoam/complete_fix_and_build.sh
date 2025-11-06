#!/bin/bash
# Complete diagnostic and build script for simpleHIPFoam
# This addresses all known issues including bashrc hanging

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}=========================================="
echo "  simpleHIPFoam Complete Fix & Build"
echo -e "==========================================${NC}\n"

# ============================================
# STEP 1: Find OpenFOAM Installation
# ============================================
echo -e "${BLUE}[1/6] Locating OpenFOAM...${NC}"

OPENFOAM_LOCATIONS=(
    "$HOME/OpenFOAM/OpenFOAM-v2412"
    "/usr/lib/openfoam/openfoam2412"
    "/opt/openfoam2412"
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
    echo -e "${RED}✗ OpenFOAM v2412 not found!${NC}"
    echo ""
    echo "Searched:"
    for loc in "${OPENFOAM_LOCATIONS[@]}"; do
        echo "  - $loc"
    done
    echo ""
    echo "Please install OpenFOAM v2412 first."
    exit 1
fi

# ============================================
# STEP 2: Extract Environment Variables
# ============================================
echo ""
echo -e "${BLUE}[2/6] Setting up OpenFOAM environment...${NC}"

# Use a timeout to prevent hanging, and extract only what we need
ENV_VARS=$(timeout 10s bash -c "
    source '$OPENFOAM_DIR/etc/bashrc' 2>/dev/null
    echo WM_PROJECT_DIR=\$WM_PROJECT_DIR
    echo WM_PROJECT_VERSION=\$WM_PROJECT_VERSION
    echo FOAM_SRC=\$FOAM_SRC
    echo FOAM_APPBIN=\$FOAM_APPBIN
    echo FOAM_USER_APPBIN=\$FOAM_USER_APPBIN
    echo FOAM_USER_LIBBIN=\$FOAM_USER_LIBBIN
    echo WM_DIR=\$WM_DIR
    echo WM_COMPILER=\$WM_COMPILER
    echo WM_COMPILE_OPTION=\$WM_COMPILE_OPTION
    echo WM_PRECISION_OPTION=\$WM_PRECISION_OPTION
    echo WM_LABEL_SIZE=\$WM_LABEL_SIZE
    echo WM_OPTIONS=\$WM_OPTIONS
    echo LIB_SRC=\$LIB_SRC
" 2>/dev/null)

if [ $? -ne 0 ] || [ -z "$ENV_VARS" ]; then
    echo -e "${YELLOW}⚠ bashrc timeout or failed, using manual setup...${NC}"
    
    # Manual environment setup
    export WM_PROJECT_DIR="$OPENFOAM_DIR"
    export WM_PROJECT_VERSION="v2412"
    export FOAM_SRC="$WM_PROJECT_DIR/src"
    export FOAM_APPBIN="$WM_PROJECT_DIR/platforms/linux64GccDPInt32Opt/bin"
    export FOAM_USER_APPBIN="$HOME/OpenFOAM/$(whoami)-v2412/platforms/linux64GccDPInt32Opt/bin"
    export FOAM_USER_LIBBIN="$HOME/OpenFOAM/$(whoami)-v2412/platforms/linux64GccDPInt32Opt/lib"
    export WM_DIR="$WM_PROJECT_DIR/wmake"
    export WM_COMPILER="Gcc"
    export WM_COMPILE_OPTION="Opt"
    export WM_PRECISION_OPTION="DP"
    export WM_LABEL_SIZE="32"
    export WM_OPTIONS="linux64GccDPInt32Opt"
    export LIB_SRC="$FOAM_SRC"
    
    # Add to PATH
    export PATH="$FOAM_APPBIN:$WM_DIR:$PATH"
    export LD_LIBRARY_PATH="$WM_PROJECT_DIR/platforms/$WM_OPTIONS/lib:$LD_LIBRARY_PATH"
    
    echo -e "${GREEN}✓ Manual environment setup complete${NC}"
else
    # Load extracted variables
    eval "$ENV_VARS"
    export $(echo "$ENV_VARS" | cut -d= -f1)
    
    # Add to PATH
    export PATH="$FOAM_APPBIN:$WM_DIR:$PATH"
    export LD_LIBRARY_PATH="$WM_PROJECT_DIR/platforms/$WM_OPTIONS/lib:$LD_LIBRARY_PATH"
    
    echo -e "${GREEN}✓ OpenFOAM environment loaded${NC}"
fi

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
# STEP 3: Verify/Fix OpenFOAM Headers
# ============================================
echo ""
echo -e "${BLUE}[3/6] Verifying OpenFOAM headers...${NC}"

CRITICAL_HEADERS=(
    "/usr/lib/openfoam/openfoam2412/src/finiteVolume/lnInclude/fvCFD.H"
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
    
    DIRS_TO_FIX=(
        "OpenFOAM"
        "finiteVolume"
        "meshTools"
        "TurbulenceModels/turbulenceModels"
        "TurbulenceModels/incompressible"
        "transportModels/incompressible/singlePhaseTransportModel"
    )
    
    for dir in "${DIRS_TO_FIX[@]}"; do
        if [ -d "$dir" ]; then
            echo "    Building: $dir/lnInclude"
            $WM_DIR/wmakeLnInclude "$dir" 2>/dev/null || {
                # Manual fallback
                mkdir -p "$dir/lnInclude"
                find "$dir" -maxdepth 1 -name "*.H" -exec ln -sf ../{} "$dir/lnInclude/" \; 2>/dev/null
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
        echo -e "${RED}✗ Still missing $STILL_MISSING headers!${NC}"
        echo "  Your OpenFOAM installation may be incomplete."
        echo ""
        echo "  Try: sudo apt-get install --reinstall openfoam2412-dev openfoam2412-source"
        echo "  Or build from source: https://www.openfoam.com/download/install-source"
        exit 1
    fi
fi

# ============================================
# STEP 4: Setup ROCm
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
    echo "  wget https://repo.radeon.com/amdgpu-install/latest/ubuntu/focal/amdgpu-install_*_all.deb"
    echo "  sudo dpkg -i amdgpu-install_*_all.deb"
    echo "  sudo amdgpu-install --usecase=rocm"
    exit 1
fi

HIP_VERSION=$(hipcc --version 2>&1 | head -1)
echo -e "${GREEN}✓ HIP found${NC}"
echo "  Location: $(which hipcc)"
echo "  Version: $HIP_VERSION"

# Check GPU
if command -v rocm-smi &> /dev/null; then
    GPU_INFO=$(rocm-smi --showproductname 2>/dev/null | grep -E "Card series|Card model" | head -1 || echo "")
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

echo -e "${GREEN}✓ Source files found${NC}"

# Fix Make/options to ensure no preprocessor issues
echo "  Fixing Make/options..."
cat > applications/solvers/simpleHIPFoam/Make/options << 'EOFOPT'
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
EOFOPT

# ============================================
# STEP 6: Build
# ============================================
echo ""
echo -e "${BLUE}[6/6] Building simpleHIPFoam...${NC}"
echo ""

cd applications/solvers/simpleHIPFoam

# Clean
echo "Cleaning previous build..."
wclean 2>/dev/null || rm -rf Make/linux64* || true

# Build
echo ""
echo "Running wmake..."
echo ""

if wmake 2>&1 | tee ../../../build.log; then
    echo ""
    echo -e "${GREEN}=========================================="
    echo "  ✓✓✓ BUILD SUCCESSFUL! ✓✓✓"
    echo -e "==========================================${NC}"
    echo ""
    
    if [ -f "$FOAM_USER_APPBIN/simpleHIPFoam" ]; then
        echo "Executable created:"
        ls -lh "$FOAM_USER_APPBIN/simpleHIPFoam"
        echo ""
        echo -e "${CYAN}Test it:${NC}"
        echo "  $FOAM_USER_APPBIN/simpleHIPFoam -help"
    else
        echo -e "${YELLOW}⚠ Executable not found at expected location${NC}"
        echo "  Expected: $FOAM_USER_APPBIN/simpleHIPFoam"
        echo ""
        echo "Searching..."
        find "$HOME/OpenFOAM" -name "simpleHIPFoam" -type f 2>/dev/null | head -3
    fi
else
    echo ""
    echo -e "${RED}=========================================="
    echo "  ✗✗✗ BUILD FAILED ✗✗✗"
    echo -e "==========================================${NC}"
    echo ""
    
    # Show relevant errors
    if grep -q "fvCFD.H: No such file" ../../../build.log; then
        echo -e "${YELLOW}Error: Cannot find fvCFD.H${NC}"
        echo "Your OpenFOAM development files may be incomplete."
    elif grep -q "hipcc.*not found" ../../../build.log; then
        echo -e "${YELLOW}Error: hipcc not properly configured${NC}"
    else
        echo "Last 30 lines of build.log:"
        tail -30 ../../../build.log
    fi
    
    exit 1
fi

cd ../../..

# ============================================
# Create convenience wrapper
# ============================================
echo ""
echo "Creating convenience script..."

cat > run_simpleHIPFoam.sh << EOFRUN
#!/bin/bash
# Wrapper to run simpleHIPFoam with proper environment

# Set OpenFOAM environment manually
export WM_PROJECT_DIR="$WM_PROJECT_DIR"
export FOAM_USER_APPBIN="$FOAM_USER_APPBIN"
export PATH="$FOAM_APPBIN:\$PATH"
export LD_LIBRARY_PATH="$WM_PROJECT_DIR/platforms/$WM_OPTIONS/lib:\$LD_LIBRARY_PATH"

# Set ROCm environment
export ROCM_PATH=/opt/rocm
export PATH=\$ROCM_PATH/bin:\$PATH
export LD_LIBRARY_PATH=\$ROCM_PATH/lib:\$LD_LIBRARY_PATH

# Run solver
$FOAM_USER_APPBIN/simpleHIPFoam "\$@"
EOFRUN

chmod +x run_simpleHIPFoam.sh

echo ""
echo -e "${GREEN}=========================================="
echo "  All Done!"
echo -e "==========================================${NC}"
echo ""
echo -e "${CYAN}Quick test:${NC}"
echo "  ./run_simpleHIPFoam.sh -help"
echo ""
echo -e "${CYAN}To use in any terminal session:${NC}"
echo "  1. Copy run_simpleHIPFoam.sh to your case directory"
echo "  2. Run: ./run_simpleHIPFoam.sh"
echo ""
echo -e "${CYAN}For permanent setup, add to ~/.bashrc:${NC}"
echo ""
echo "  export PATH=$FOAM_USER_APPBIN:\$PATH"
echo "  export PATH=/opt/rocm/bin:\$PATH"
echo "  export LD_LIBRARY_PATH=/opt/rocm/lib:\$LD_LIBRARY_PATH"
echo ""