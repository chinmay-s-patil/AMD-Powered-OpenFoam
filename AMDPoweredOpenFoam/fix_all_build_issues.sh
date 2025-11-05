#!/bin/bash
# Complete fix for all simpleHIPFoam build issues

set -e

echo "=========================================="
echo "  Fixing ALL simpleHIPFoam Build Issues"
echo "=========================================="

# Navigate to solver directory
cd applications/solvers/simpleHIPFoam

echo ""
echo "[1/5] Fixing Make/options (removing preprocessor directives)..."

# Create clean Make/options without any # comments that look like directives
cat > Make/options << 'EOF'
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

echo "✓ Make/options cleaned"

echo ""
echo "[2/5] Adding missing newlines to all .H and .C files..."

# Function to ensure newline at end of file
ensure_newline() {
    local file="$1"
    if [ -f "$file" ]; then
        # Check if file ends with newline
        if [ -n "$(tail -c1 "$file")" ]; then
            echo "" >> "$file"
            echo "  ✓ Fixed: $file"
        fi
    fi
}

# Fix all header and source files
for file in *.H *.C hipSolver/*.H hipSolver/*.C; do
    if [ -f "$file" ]; then
        ensure_newline "$file"
    fi
done

echo "✓ Newlines added"

echo ""
echo "[3/5] Verifying include paths..."

# Check if OpenFOAM environment is loaded
if [ -z "$WM_PROJECT_DIR" ]; then
    echo "ERROR: OpenFOAM environment not loaded!"
    echo "Please run: source /opt/openfoam2412/etc/bashrc"
    exit 1
fi

echo "  OpenFOAM: $WM_PROJECT_VERSION"
echo "  WM_PROJECT_DIR: $WM_PROJECT_DIR"
echo "  LIB_SRC: $LIB_SRC"

# Check critical include files
if [ ! -f "$LIB_SRC/finiteVolume/lnInclude/fvCFD.H" ]; then
    echo "ERROR: fvCFD.H not found at $LIB_SRC/finiteVolume/lnInclude/"
    echo "OpenFOAM may not be properly installed."
    exit 1
fi

echo "✓ Include paths verified"

echo ""
echo "[4/5] Checking ROCm installation..."

# Check hipcc
if ! command -v hipcc &> /dev/null; then
    echo "ERROR: hipcc not found in PATH"
    echo "Please add ROCm to PATH: export PATH=/opt/rocm/bin:\$PATH"
    exit 1
fi

hipcc --version | head -1
echo "  hipcc: $(which hipcc)"

# Check ROCm libraries
if [ ! -f /opt/rocm/lib/libamdhip64.so ]; then
    echo "WARNING: libamdhip64.so not found at /opt/rocm/lib/"
    echo "You may need to adjust library paths"
fi

if [ ! -f /opt/rocm/lib/librocsparse.so ]; then
    echo "WARNING: librocsparse.so not found at /opt/rocm/lib/"
fi

echo "✓ ROCm installation checked"

echo ""
echo "[5/5] Cleaning previous build artifacts..."

# Remove old build files
wclean 2>/dev/null || {
    rm -rf Make/linux64*
    echo "  Manual cleanup done"
}

echo "✓ Cleaned"

echo ""
echo "=========================================="
echo "  All Fixes Applied Successfully!"
echo "=========================================="
echo ""
echo "Now try building with:"
echo "  cd ../../.."
echo "  ./Allwmake"
echo ""