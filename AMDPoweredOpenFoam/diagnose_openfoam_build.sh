#!/bin/bash
# Diagnose OpenFOAM source build and fix issues

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}=========================================="
echo "  OpenFOAM Build Diagnosis"
echo -e "==========================================${NC}\n"

OPENFOAM_DIR="$HOME/OpenFOAM/OpenFOAM-v2412"

# 1. Check if directory exists
echo -e "${BLUE}[1/4] Checking OpenFOAM directory...${NC}"

if [ ! -d "$OPENFOAM_DIR" ]; then
    echo -e "${RED}✗ Directory not found: $OPENFOAM_DIR${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Directory exists${NC}"

# 2. Check bashrc
echo ""
echo -e "${BLUE}[2/4] Checking bashrc file...${NC}"

if [ ! -f "$OPENFOAM_DIR/etc/bashrc" ]; then
    echo -e "${RED}✗ bashrc not found!${NC}"
    exit 1
fi

echo -e "${GREEN}✓ bashrc exists${NC}"

# 3. Check if build completed
echo ""
echo -e "${BLUE}[3/4] Checking if OpenFOAM built successfully...${NC}"

# Check for key executables
if [ -f "$OPENFOAM_DIR/platforms/linux64GccDPInt32Opt/bin/blockMesh" ]; then
    echo -e "${GREEN}✓ blockMesh found - build appears successful${NC}"
else
    echo -e "${RED}✗ blockMesh not found - build incomplete!${NC}"
    echo ""
    echo "OpenFOAM build did not complete successfully."
    echo ""
    echo "To rebuild:"
    echo "  cd $OPENFOAM_DIR"
    echo "  ./Allwmake -j$(nproc) 2>&1 | tee make.log"
    echo ""
    exit 1
fi

# Check for wmake
if [ -f "$OPENFOAM_DIR/wmake/wmake" ]; then
    echo -e "${GREEN}✓ wmake found${NC}"
else
    echo -e "${RED}✗ wmake not found${NC}"
    exit 1
fi

# 4. Try to source bashrc and check environment
echo ""
echo -e "${BLUE}[4/4] Testing environment setup...${NC}"

# Source in a subshell to avoid hanging the main script
timeout 5 bash -c "source $OPENFOAM_DIR/etc/bashrc && echo 'SUCCESS'" > /tmp/openfoam_test.log 2>&1

if grep -q "SUCCESS" /tmp/openfoam_test.log; then
    echo -e "${GREEN}✓ bashrc sources successfully${NC}"
else
    echo -e "${RED}✗ bashrc hangs or fails${NC}"
    echo ""
    echo "Output:"
    cat /tmp/openfoam_test.log
    echo ""
    echo -e "${YELLOW}Possible issues:${NC}"
    echo "  1. MPI configuration problem"
    echo "  2. Missing dependencies"
    echo "  3. Path issues"
    echo ""
    echo "Let's check what's in bashrc..."
    grep -E "export|WM_|FOAM_" "$OPENFOAM_DIR/etc/bashrc" | head -20
    exit 1
fi

# Get environment variables
eval "$(bash -c "source $OPENFOAM_DIR/etc/bashrc 2>/dev/null && env" | grep -E '^(WM_|FOAM_)' | sed 's/^/export /')"

if [ -n "$WM_PROJECT_DIR" ]; then
    echo -e "${GREEN}✓ Environment variables set correctly${NC}"
    echo "  WM_PROJECT_DIR: $WM_PROJECT_DIR"
    echo "  WM_PROJECT_VERSION: $WM_PROJECT_VERSION"
    echo "  FOAM_APPBIN: $FOAM_APPBIN"
else
    echo -e "${RED}✗ Environment variables not set${NC}"
    exit 1
fi

# Check for fvCFD.H
if [ -f "$OPENFOAM_DIR/src/finiteVolume/lnInclude/fvCFD.H" ]; then
    echo -e "${GREEN}✓ fvCFD.H found${NC}"
else
    echo -e "${YELLOW}⚠ fvCFD.H not found${NC}"
    echo "  Building lnInclude directories..."
    cd "$OPENFOAM_DIR/src"
    wmakeLnInclude finiteVolume 2>/dev/null || true
fi

echo ""
echo -e "${GREEN}=========================================="
echo "  Diagnosis Complete!"
echo -e "==========================================${NC}"
echo ""
echo "OpenFOAM appears to be properly built."
echo ""
echo "To build simpleHIPFoam, create this build script:"
echo ""

cat > /tmp/simple_build.sh << 'EOFBUILD'
#!/bin/bash
# Simple build script for simpleHIPFoam

# Manual environment setup (avoiding bashrc issues)
export WM_PROJECT_DIR="$HOME/OpenFOAM/OpenFOAM-v2412"
export WM_PROJECT_VERSION="v2412"
export FOAM_SRC="$WM_PROJECT_DIR/src"
export FOAM_APPBIN="$WM_PROJECT_DIR/platforms/linux64GccDPInt32Opt/bin"
export FOAM_USER_APPBIN="$HOME/OpenFOAM/indigo-v2412/platforms/linux64GccDPInt32Opt/bin"
export FOAM_USER_LIBBIN="$HOME/OpenFOAM/indigo-v2412/platforms/linux64GccDPInt32Opt/lib"
export WM_DIR="$WM_PROJECT_DIR/wmake"
export WM_COMPILER="Gcc"
export WM_COMPILE_OPTION="Opt"
export WM_PRECISION_OPTION="DP"
export WM_LABEL_SIZE="32"
export WM_OPTIONS="linux64GccDPInt32Opt"

# Add to PATH
export PATH="$WM_PROJECT_DIR/platforms/linux64GccDPInt32Opt/bin:$WM_DIR:$PATH"
export LD_LIBRARY_PATH="$WM_PROJECT_DIR/platforms/linux64GccDPInt32Opt/lib:$LD_LIBRARY_PATH"

# ROCm
export ROCM_PATH=/opt/rocm
export PATH=$ROCM_PATH/bin:$PATH
export LD_LIBRARY_PATH=$ROCM_PATH/lib:$LD_LIBRARY_PATH

# Create user directories if needed
mkdir -p "$FOAM_USER_APPBIN" "$FOAM_USER_LIBBIN"

echo "Environment set up!"
echo "WM_PROJECT_DIR: $WM_PROJECT_DIR"
echo "FOAM_USER_APPBIN: $FOAM_USER_APPBIN"

# Build
cd applications/solvers/simpleHIPFoam
wclean 2>/dev/null || rm -rf Make/linux64* || true

echo ""
echo "Building simpleHIPFoam..."
wmake 2>&1 | tee ../../../build.log

if [ $? -eq 0 ]; then
    echo ""
    echo "✓ Build successful!"
    ls -lh "$FOAM_USER_APPBIN/simpleHIPFoam"
else
    echo ""
    echo "✗ Build failed - check build.log"
    tail -50 ../../../build.log
fi
EOFBUILD

cat /tmp/simple_build.sh

echo ""
echo -e "${CYAN}Copy this script to your AMDPoweredOpenFoam directory and run it:${NC}"
echo ""
echo "  cp /tmp/simple_build.sh /media/indigo/Shadow\\'s\\ Retreat/Repository/Projects/ROCm\\ Trials/AMDPoweredOpenFoam/"
echo "  cd /media/indigo/Shadow\\'s\\ Retreat/Repository/Projects/ROCm\\ Trials/AMDPoweredOpenFoam/"
echo "  chmod +x simple_build.sh"
echo "  ./simple_build.sh"