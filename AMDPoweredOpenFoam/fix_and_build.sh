#!/bin/bash
# Complete fix and build script for simpleHIPFoam
# This will diagnose and fix OpenFOAM header issues, then build

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

# 1. Source OpenFOAM
echo -e "${BLUE}[1/6] Loading OpenFOAM environment...${NC}"
source /usr/lib/openfoam/openfoam2412/etc/bashrc

echo -e "${GREEN}✓ OpenFOAM $WM_PROJECT_VERSION loaded${NC}"
echo "  WM_PROJECT_DIR: $WM_PROJECT_DIR"
echo "  FOAM_SRC: $FOAM_SRC"

# 2. Check if we need to install OpenFOAM development files
echo ""
echo -e "${BLUE}[2/6] Checking OpenFOAM development files...${NC}"

if [ ! -d "$FOAM_SRC" ]; then
    echo -e "${RED}✗ FOAM_SRC directory not found!${NC}"
    echo ""
    echo "Installing OpenFOAM development packages..."
    sudo apt-get update
    sudo apt-get install -y openfoam2412-dev openfoam2412-source
    
    # Re-source after installation
    source /usr/lib/openfoam/openfoam2412/etc/bashrc
fi

# 3. Check and create lnInclude directories
echo ""
echo -e "${BLUE}[3/6] Checking/creating lnInclude directories...${NC}"

cd "$FOAM_SRC"

# Critical directories that need lnInclude
CRITICAL_DIRS=(
    "OpenFOAM"
    "finiteVolume"
    "meshTools"
    "sampling"
    "TurbulenceModels/turbulenceModels"
    "TurbulenceModels/incompressible"
    "transportModels/incompressible/singlePhaseTransportModel"
    "dynamicMesh"
    "dynamicFvMesh"
)

for dir in "${CRITICAL_DIRS[@]}"; do
    if [ -d "$dir" ]; then
        echo "  Processing: $dir"
        
        # Check if lnInclude exists and has files
        if [ ! -d "$dir/lnInclude" ] || [ -z "$(ls -A "$dir/lnInclude" 2>/dev/null)" ]; then
            echo "    Creating lnInclude..."
            wmakeLnInclude "$dir" 2>/dev/null || {
                # Manual creation if wmakeLnInclude fails
                mkdir -p "$dir/lnInclude"
                cd "$dir"
                find . -maxdepth 1 -name "*.H" -exec ln -sf ../{} lnInclude/ \;
                cd "$FOAM_SRC"
            }
        fi
        
        # Verify fvCFD.H specifically
        if [ "$dir" = "finiteVolume" ]; then
            if [ -f "$dir/lnInclude/fvCFD.H" ]; then
                echo -e "    ${GREEN}✓ fvCFD.H found${NC}"
            else
                echo -e "    ${YELLOW}⚠ fvCFD.H not found, creating manually...${NC}"
                cd "$dir"
                if [ -f "fvCFD.H" ]; then
                    ln -sf ../fvCFD.H lnInclude/
                elif [ -f "cfdTools/general/include/fvCFD.H" ]; then
                    ln -sf ../cfdTools/general/include/fvCFD.H lnInclude/
                fi
                cd "$FOAM_SRC"
            fi
        fi
    fi
done

# 4. Verify critical headers exist
echo ""
echo -e "${BLUE}[4/6] Verifying critical headers...${NC}"

CRITICAL_HEADERS=(
    "$FOAM_SRC/finiteVolume/lnInclude/fvCFD.H"
    "$FOAM_SRC/OpenFOAM/lnInclude/lduMatrix.H"
    "$FOAM_SRC/finiteVolume/lnInclude/fvMesh.H"
)

ALL_FOUND=true
for header in "${CRITICAL_HEADERS[@]}"; do
    if [ -f "$header" ]; then
        echo -e "  ${GREEN}✓${NC} $(basename $header)"
    else
        echo -e "  ${RED}✗${NC} $(basename $header) - NOT FOUND"
        ALL_FOUND=false
    fi
done

if [ "$ALL_FOUND" = false ]; then
    echo ""
    echo -e "${RED}ERROR: Critical headers missing!${NC}"
    echo ""
    echo "Your OpenFOAM installation appears incomplete."
    echo "Try reinstalling with:"
    echo "  sudo apt-get install --reinstall openfoam2412-default openfoam2412-dev openfoam2412-source"
    exit 1
fi

# 5. Setup ROCm
echo ""
echo -e "${BLUE}[5/6] Setting up ROCm environment...${NC}"

export ROCM_PATH=/opt/rocm
export PATH=$ROCM_PATH/bin:$PATH
export LD_LIBRARY_PATH=$ROCM_PATH/lib:$LD_LIBRARY_PATH

if command -v hipcc &> /dev/null; then
    HIP_VERSION=$(hipcc --version | head -1)
    echo -e "${GREEN}✓ HIP found${NC}"
    echo "  Location: $(which hipcc)"
    echo "  Version: $HIP_VERSION"
else
    echo -e "${RED}✗ hipcc not found!${NC}"
    echo "Please install ROCm:"
    echo "  wget https://repo.radeon.com/amdgpu-install/latest/ubuntu/focal/amdgpu-install_*_all.deb"
    echo "  sudo dpkg -i amdgpu-install_*_all.deb"
    echo "  sudo amdgpu-install --usecase=rocm"
    exit 1
fi

# 6. Build simpleHIPFoam
echo ""
echo -e "${BLUE}[6/6] Building simpleHIPFoam...${NC}"
echo ""

# Go back to project directory
cd "$OLDPWD"

# Navigate to solver
cd applications/solvers/simpleHIPFoam

# Clean previous build
echo "Cleaning previous build..."
wclean 2>/dev/null || rm -rf Make/linux64* || true

# Build
echo ""
echo "Building with wmake..."
echo ""

# Use standard GCC for now (hipcc integration comes later)
export WM_COMPILER=Gcc
export WM_COMPILE_OPTION=Opt

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
        echo "  simpleHIPFoam -help"
        echo ""
        echo -e "${CYAN}Next steps:${NC}"
        echo "  1. cd to your OpenFOAM case directory"
        echo "  2. Add GPU settings to system/fvSolution (see Quickstart.md)"
        echo "  3. Run: simpleHIPFoam"
    fi
else
    echo ""
    echo -e "${RED}=========================================="
    echo "  ✗✗✗ BUILD FAILED ✗✗✗"
    echo -e "==========================================${NC}"
    echo ""
    echo "Check build.log for details"
    
    # Try to diagnose
    if grep -q "fvCFD.H: No such file" ../../../build.log; then
        echo ""
        echo -e "${YELLOW}Still can't find fvCFD.H!${NC}"
        echo ""
        echo "Searching for it manually..."
        find /usr/lib/openfoam/openfoam2412 -name "fvCFD.H" 2>/dev/null | head -5
        echo ""
        echo "Your OpenFOAM installation may need manual repair."
        echo "Consider building OpenFOAM from source."
    fi
    
    exit 1
fi

cd ../../..

echo ""
echo -e "${GREEN}All done!${NC}"