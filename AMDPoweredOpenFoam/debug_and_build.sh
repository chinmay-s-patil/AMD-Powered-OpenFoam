#!/bin/bash
# Debug and build script - shows exactly what's happening

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "=========================================="
echo "  Debugging wmake include paths"
echo "=========================================="
echo ""

# Check if already sourced
if [ -z "$WM_PROJECT_DIR" ]; then
    echo "Sourcing OpenFOAM environment..."
    # Use timeout to prevent hanging
    timeout 10s bash -c "source /usr/lib/openfoam/openfoam2406/etc/bashrc && env" > /tmp/of_env.txt 2>/dev/null || {
        echo -e "${YELLOW}Warning: bashrc timeout, using manual setup${NC}"
        export WM_PROJECT_DIR="/usr/lib/openfoam/openfoam2406"
        export FOAM_SRC="$WM_PROJECT_DIR/src"
        export LIB_SRC="$FOAM_SRC"
        export WM_DIR="$WM_PROJECT_DIR/wmake"
        export WM_OPTIONS="linux64GccDPInt32Opt"
        export FOAM_APPBIN="$WM_PROJECT_DIR/platforms/$WM_OPTIONS/bin"
        export FOAM_LIBBIN="$WM_PROJECT_DIR/platforms/$WM_OPTIONS/lib"
        export FOAM_USER_APPBIN="$HOME/OpenFOAM/$(whoami)-v2406/platforms/$WM_OPTIONS/bin"
        export PATH="$FOAM_APPBIN:$WM_DIR:$PATH"
        export LD_LIBRARY_PATH="$FOAM_LIBBIN:$LD_LIBRARY_PATH"
        mkdir -p "$FOAM_USER_APPBIN"
    }
    
    # Load from temp file if it worked
    if [ -f /tmp/of_env.txt ]; then
        eval "$(grep -E '^(WM_|FOAM_|LIB_)' /tmp/of_env.txt | sed 's/^/export /')"
        rm /tmp/of_env.txt
    fi
else
    echo "OpenFOAM already sourced"
fi

echo "Environment:"
echo "  FOAM_SRC: $FOAM_SRC"
echo "  LIB_SRC: $LIB_SRC"
echo "  WM_DIR: $WM_DIR"
echo ""

# Go to solver directory
cd applications/solvers/simpleHIPFoam

echo "Cleaning ALL build artifacts..."
rm -rf Make/linux64* 2>/dev/null || true
wclean 2>/dev/null || true

echo ""
echo "Creating Make/options..."

# Create options file - try with $(LIB_SRC) first
cat > Make/options << 'EOF'
EXE_INC = \
    -I$(LIB_SRC)/finiteVolume/lnInclude \
    -I$(LIB_SRC)/OpenFOAM/lnInclude \
    -I$(LIB_SRC)/OSspecific/POSIX/lnInclude \
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

echo "Make/options created with \$(LIB_SRC) variables"
echo ""
echo "Content:"
cat Make/options
echo ""

# Fix newlines
for file in *.C *.H hipSolver/*.C hipSolver/*.H; do
    if [ -f "$file" ] && [ -n "$(tail -c1 "$file" 2>/dev/null)" ]; then
        echo "" >> "$file"
    fi
done

echo "Running wmake with verbose output..."
echo ""

# Run wmake and capture
wmake 2>&1 | tee ../../../build.log

BUILD_EXIT=${PIPESTATUS[0]}

echo ""
echo "=========================================="

if [ $BUILD_EXIT -eq 0 ]; then
    echo -e "${GREEN}BUILD SUCCESS!${NC}"
    echo ""
    if [ -f "$FOAM_USER_APPBIN/simpleHIPFoam" ]; then
        ls -lh "$FOAM_USER_APPBIN/simpleHIPFoam"
    fi
else
    echo -e "${RED}BUILD FAILED!${NC}"
    echo ""
    
    # Show the actual compiler command that was used
    echo "Compiler command used:"
    grep "^g++" ../../../build.log | head -1
    echo ""
    
    # Check if preprocessed options exists
    if [ -f "Make/linux64GccDPInt32Opt/options" ]; then
        echo "Preprocessed Make/linux64GccDPInt32Opt/options content:"
        cat Make/linux64GccDPInt32Opt/options
        echo ""
    fi
    
    # Show what EXE_INC should have been
    echo "EXE_INC should contain:"
    echo "  -I$FOAM_SRC/finiteVolume/lnInclude"
    echo "  -I$FOAM_SRC/OpenFOAM/lnInclude"
    echo ""
    
    # Check if fvCFD.H exists
    if [ -f "$FOAM_SRC/finiteVolume/lnInclude/fvCFD.H" ]; then
        echo -e "${GREEN}fvCFD.H exists at: $FOAM_SRC/finiteVolume/lnInclude/fvCFD.H${NC}"
    else
        echo -e "${RED}fvCFD.H NOT FOUND!${NC}"
    fi
    
    echo ""
    echo "Last 20 lines of error:"
    tail -20 ../../../build.log
fi