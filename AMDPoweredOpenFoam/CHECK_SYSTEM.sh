#!/bin/bash
# System diagnostic - find out what's installed and where

echo "================================================"
echo "  System Diagnostic for simpleHIPFoam"
echo "================================================"
echo ""

echo "[1] Checking OpenFOAM installations..."
echo ""

# Check common locations
LOCATIONS=(
    "$HOME/OpenFOAM/OpenFOAM-v2412"
    "/usr/lib/openfoam/openfoam2412"
    "/opt/openfoam2412"
)

for loc in "${LOCATIONS[@]}"; do
    if [ -d "$loc" ]; then
        echo "✓ Found: $loc"
        
        if [ -f "$loc/etc/bashrc" ]; then
            echo "  - bashrc: YES"
        else
            echo "  - bashrc: NO"
        fi
        
        if [ -d "$loc/src" ]; then
            echo "  - src/: YES"
        else
            echo "  - src/: NO"
        fi
        
        if [ -f "$loc/src/finiteVolume/lnInclude/fvCFD.H" ]; then
            echo "  - fvCFD.H: YES ✓"
        else
            echo "  - fvCFD.H: NO ✗"
        fi
        
        echo ""
    else
        echo "✗ Not found: $loc"
    fi
done

echo ""
echo "[2] Checking ROCm/HIP..."
echo ""

if command -v hipcc &> /dev/null; then
    echo "✓ hipcc found: $(which hipcc)"
    hipcc --version | head -1
else
    echo "✗ hipcc NOT found"
fi

if [ -d "/opt/rocm" ]; then
    echo "✓ ROCm directory: /opt/rocm"
else
    echo "✗ ROCm directory NOT found"
fi

if command -v rocm-smi &> /dev/null; then
    echo ""
    echo "GPU info:"
    rocm-smi --showproductname 2>/dev/null | head -5
else
    echo "✗ rocm-smi NOT found"
fi

echo ""
echo "[3] Checking wmake..."
echo ""

# Try to find wmake
WMAKE_LOCS=(
    "$HOME/OpenFOAM/OpenFOAM-v2412/wmake/wmake"
    "/usr/lib/openfoam/openfoam2412/wmake/wmake"
    "/opt/openfoam2412/wmake/wmake"
)

for wm in "${WMAKE_LOCS[@]}"; do
    if [ -f "$wm" ]; then
        echo "✓ Found wmake: $wm"
        break
    fi
done

if command -v wmake &> /dev/null; then
    echo "✓ wmake in PATH: $(which wmake)"
else
    echo "✗ wmake NOT in PATH (this is normal before sourcing bashrc)"
fi

echo ""
echo "[4] Checking project files..."
echo ""

if [ -f "applications/solvers/simpleHIPFoam/simpleHIPFoam.C" ]; then
    echo "✓ simpleHIPFoam.C found"
else
    echo "✗ simpleHIPFoam.C NOT found"
    echo "  Are you in AMDPoweredOpenFoam directory?"
fi

if [ -f "applications/solvers/simpleHIPFoam/hipSolver/hipSIMPLE.C" ]; then
    echo "✓ hipSIMPLE.C found"
else
    echo "✗ hipSIMPLE.C NOT found"
fi

echo ""
echo "================================================"
echo "  Diagnosis Complete"
echo "================================================"
echo ""
echo "RECOMMENDATION:"
echo ""

# Determine best approach
if [ -f "$HOME/OpenFOAM/OpenFOAM-v2412/src/finiteVolume/lnInclude/fvCFD.H" ]; then
    echo "  Source-built OpenFOAM detected and appears complete."
    echo "  Run: ./BUILD_NOW.sh"
elif [ -f "/usr/lib/openfoam/openfoam2412/src/finiteVolume/lnInclude/fvCFD.H" ]; then
    echo "  Package-installed OpenFOAM detected and appears complete."
    echo "  Run: ./BUILD_NOW.sh"
else
    echo "  OpenFOAM installation appears incomplete!"
    echo ""
    echo "  Option 1: Install from packages (easier)"
    echo "    sudo apt-get install openfoam2412-dev openfoam2412-source"
    echo "    Then run: ./complete_fix_and_build.sh"
    echo ""
    echo "  Option 2: Build from source (takes time but reliable)"
    echo "    cd ~/OpenFOAM"
    echo "    wget https://dl.openfoam.com/source/v2412/OpenFOAM-v2412.tgz"
    echo "    tar -xzf OpenFOAM-v2412.tgz"
    echo "    cd OpenFOAM-v2412"
    echo "    source etc/bashrc"
    echo "    ./Allwmake -j -s -q"
    echo "    (This takes 1-2 hours)"
fi

echo ""