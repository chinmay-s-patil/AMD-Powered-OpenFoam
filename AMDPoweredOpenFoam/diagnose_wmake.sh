#!/bin/bash
# Diagnose why wmake isn't using Make/options

echo "=========================================="
echo "  Diagnosing wmake issue"
echo "=========================================="
echo ""

cd applications/solvers/simpleHIPFoam

echo "1. Checking Make/options file:"
if [ -f "Make/options" ]; then
    echo "✓ Make/options exists"
    ls -la Make/options
    echo ""
    echo "First 10 lines:"
    head -10 Make/options
    echo ""
    echo "Checking for DOS line endings:"
    file Make/options
    echo ""
else
    echo "✗ Make/options NOT FOUND!"
    exit 1
fi

echo "2. Checking Make/files:"
if [ -f "Make/files" ]; then
    echo "✓ Make/files exists"
    cat Make/files
    echo ""
else
    echo "✗ Make/files NOT FOUND!"
fi

echo "3. Checking OpenFOAM environment:"
echo "WM_PROJECT_DIR: $WM_PROJECT_DIR"
echo "WM_OPTIONS: $WM_OPTIONS"
echo "WM_DIR: $WM_DIR"
echo ""

echo "4. Trying wmake with debugging:"
echo ""

# Set wmake to verbose mode
export WM_VERBOSE_FLAGS=1

# Run wmake to just build dependencies first
echo "Building dependencies only..."
wmakeLnInclude . 2>&1 || true
echo ""

# Check what wmake would do
echo "What wmake sees:"
$WM_DIR/wmake -debug 2>&1 | head -50
echo ""

echo "5. Manually test the compiler command:"
echo ""

# Try compiling with the include paths manually
echo "Testing manual compile:"
g++ -std=c++14 \
    -I/usr/lib/openfoam/openfoam2406/src/finiteVolume/lnInclude \
    -I/usr/lib/openfoam/openfoam2406/src/OpenFOAM/lnInclude \
    -I/usr/lib/openfoam/openfoam2406/src/OSspecific/POSIX/lnInclude \
    -O3 -fPIC -D__HIP_PLATFORM_AMD__ \
    -E simpleHIPFoam.C 2>&1 | head -20

if [ $? -eq 0 ]; then
    echo ""
    echo "✓ Manual compile with include paths WORKS!"
    echo "  This proves the paths are correct, wmake just isn't using them"
else
    echo ""
    echo "✗ Even manual compile fails - paths might be wrong"
fi