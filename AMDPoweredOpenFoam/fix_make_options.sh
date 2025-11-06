#!/bin/bash
# Fix Make/options with absolute paths
# This script creates a working Make/options file

echo "Fixing Make/options with absolute paths..."

# Determine which OpenFOAM to use
if [ -f "/home/indigo/OpenFOAM/OpenFOAM-v2412/src/finiteVolume/lnInclude/fvCFD.H" ]; then
    FOAM_DIR="/home/indigo/OpenFOAM/OpenFOAM-v2412"
    echo "Using source-built OpenFOAM: $FOAM_DIR"
elif [ -f "/usr/lib/openfoam/openfoam2412/src/finiteVolume/lnInclude/fvCFD.H" ]; then
    FOAM_DIR="/usr/lib/openfoam/openfoam2412"
    echo "Using package OpenFOAM: $FOAM_DIR"
else
    echo "ERROR: Cannot find OpenFOAM installation!"
    exit 1
fi

# Create Make/options with ABSOLUTE paths (no variables)
cat > applications/solvers/simpleHIPFoam/Make/options << EOF
EXE_INC = \\
    -I$FOAM_DIR/src/finiteVolume/lnInclude \\
    -I$FOAM_DIR/src/meshTools/lnInclude \\
    -I$FOAM_DIR/src/sampling/lnInclude \\
    -I$FOAM_DIR/src/TurbulenceModels/turbulenceModels/lnInclude \\
    -I$FOAM_DIR/src/TurbulenceModels/incompressible/lnInclude \\
    -I$FOAM_DIR/src/transportModels \\
    -I$FOAM_DIR/src/transportModels/incompressible/singlePhaseTransportModel \\
    -I$FOAM_DIR/src/dynamicMesh/lnInclude \\
    -I$FOAM_DIR/src/dynamicFvMesh/lnInclude \\
    -I/opt/rocm/include \\
    -I/opt/rocm/include/hip \\
    -I/opt/rocm/include/rocsparse \\
    -I/opt/rocm/include/rocblas

EXE_LIBS = \\
    -lfiniteVolume \\
    -lfvOptions \\
    -lmeshTools \\
    -lsampling \\
    -lturbulenceModels \\
    -lincompressibleTurbulenceModels \\
    -lincompressibleTransportModels \\
    -ldynamicMesh \\
    -ldynamicFvMesh \\
    -L/opt/rocm/lib \\
    -lamdhip64 \\
    -lrocsparse \\
    -lrocblas

c++FLAGS = -std=c++14 -O3 -fPIC -D__HIP_PLATFORM_AMD__
EOF

echo "✓ Created Make/options with absolute paths"
echo ""
echo "Contents:"
head -20 applications/solvers/simpleHIPFoam/Make/options
echo ""
echo "Now try building again:"
echo "  cd applications/solvers/simpleHIPFoam"
echo "  wclean"
echo "  wmake"