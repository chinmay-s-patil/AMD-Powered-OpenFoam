#!/bin/bash
# install.sh - Complete setup for simpleHIPFoam
# Run this from AMDPoweredOpenFoam directory

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}"
cat << "EOF"
╔═══════════════════════════════════════════╗
║                                           ║
║       simpleHIPFoam Installation          ║
║   HIP-Accelerated OpenFOAM SIMPLE Solver  ║
║                                           ║
╚═══════════════════════════════════════════╝
EOF
echo -e "${NC}"

# 1. Check OpenFOAM
echo -e "${BLUE}[1/5] Checking OpenFOAM environment...${NC}"
if [ -z "$WM_PROJECT_DIR" ]; then
    echo -e "${RED}ERROR: OpenFOAM environment not loaded!${NC}"
    echo "Please run: source /opt/openfoam2412/etc/bashrc"
    exit 1
fi
echo -e "${GREEN}✓ OpenFOAM $WM_PROJECT_VERSION detected${NC}"

# 2. Check ROCm/HIP
echo -e "${BLUE}[2/5] Checking ROCm/HIP installation...${NC}"

# Set ROCm paths
export ROCM_PATH=${ROCM_PATH:-/opt/rocm}
export PATH=$ROCM_PATH/bin:$PATH
export LD_LIBRARY_PATH=$ROCM_PATH/lib:$LD_LIBRARY_PATH

# Find hipcc
HIPCC_PATH=""
if [ -f "/opt/rocm/bin/hipcc" ]; then
    HIPCC_PATH="/opt/rocm/bin/hipcc"
elif [ -f "/opt/rocm-7.1.0/bin/hipcc" ]; then
    HIPCC_PATH="/opt/rocm-7.1.0/bin/hipcc"
    export ROCM_PATH=/opt/rocm-7.1.0
elif command -v hipcc >/dev/null 2>&1; then
    HIPCC_PATH=$(which hipcc)
fi

if [ -z "$HIPCC_PATH" ]; then
    echo -e "${RED}ERROR: hipcc not found!${NC}"
    echo "Checked: /opt/rocm/bin/hipcc, /opt/rocm-7.1.0/bin/hipcc, PATH"
    exit 1
fi

HIP_VERSION=$($HIPCC_PATH --version 2>&1 | head -n 1)
echo -e "${GREEN}✓ HIP detected: $HIP_VERSION${NC}"

# 3. Check GPU
echo -e "${BLUE}[3/5] Checking AMD GPU...${NC}"
if command -v rocm-smi &> /dev/null; then
    GPU_NAME=$(rocm-smi --showproductname 2>/dev/null | grep "Card series" | head -1 | awk -F: '{print $2}' | xargs)
    if [ -z "$GPU_NAME" ]; then
        GPU_NAME=$(rocm-smi --showproductname 2>/dev/null | grep "Card model" | head -1 | awk -F: '{print $2}' | xargs)
    fi
    echo -e "${GREEN}✓ GPU detected: ${GPU_NAME:-Unknown AMD GPU}${NC}"
else
    echo -e "${YELLOW}⚠ rocm-smi not found, cannot detect GPU${NC}"
fi

# 4. Build simpleHIPFoam
echo -e "${BLUE}[4/5] Building simpleHIPFoam...${NC}"

# Ensure we're in the right directory
if [ ! -f "applications/solvers/simpleHIPFoam/simpleHIPFoam.C" ]; then
    echo -e "${RED}ERROR: simpleHIPFoam source files not found!${NC}"
    echo "Are you in the AMDPoweredOpenFoam directory?"
    exit 1
fi

# Set ROCm paths
export ROCM_PATH=${ROCM_PATH:-/opt/rocm}
export PATH=$ROCM_PATH/bin:$PATH
export LD_LIBRARY_PATH=$ROCM_PATH/lib:$LD_LIBRARY_PATH

# Build
chmod +x Allwmake Allclean
./Allwmake 2>&1 | tee build.log

if [ $? -ne 0 ]; then
    echo -e "${RED}✗ Build failed! Check build.log for details${NC}"
    exit 1
fi

# Verify executable
if [ ! -f "$FOAM_USER_APPBIN/simpleHIPFoam" ]; then
    echo -e "${RED}✗ Executable not created!${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Build successful!${NC}"
echo -e "  Executable: $FOAM_USER_APPBIN/simpleHIPFoam"

# 5. Test installation
echo -e "${BLUE}[5/5] Testing installation...${NC}"

# Quick version check
if simpleHIPFoam -help &> /dev/null; then
    echo -e "${GREEN}✓ simpleHIPFoam is executable${NC}"
else
    echo -e "${RED}✗ Cannot run simpleHIPFoam${NC}"
    exit 1
fi

# Create benchmark script
echo -e "${BLUE}Creating benchmark script...${NC}"
cat > benchmark.sh << 'EOFBENCH'
#!/bin/bash
# Quick benchmark script

echo "Running quick benchmark..."
cd $(mktemp -d)

# Create tiny cavity case
cat > blockMeshDict << 'EOF'
FoamFile
{
    version     2.0;
    format      ascii;
    class       dictionary;
    object      blockMeshDict;
}

vertices
(
    (0 0 0) (0.1 0 0) (0.1 0.1 0) (0 0.1 0)
    (0 0 0.01) (0.1 0 0.01) (0.1 0.1 0.01) (0 0.1 0.01)
);

blocks
(
    hex (0 1 2 3 4 5 6 7) (50 50 1) simpleGrading (1 1 1)
);

edges ();
boundary
(
    movingWall { type wall; faces ((3 7 6 2)); }
    fixedWalls { type wall; faces ((0 4 7 3) (0 1 5 4) (1 2 6 5)); }
    frontAndBack { type empty; faces ((0 3 2 1) (4 5 6 7)); }
);
EOF

mkdir -p 0 system constant
cp blockMeshDict system/
blockMesh -silent

# Minimal case setup
cat > 0/U << 'EOF'
FoamFile { version 2.0; format ascii; class volVectorField; object U; }
dimensions [0 1 -1 0 0 0 0];
internalField uniform (0 0 0);
boundaryField
{
    movingWall { type fixedValue; value uniform (1 0 0); }
    fixedWalls { type noSlip; }
    frontAndBack { type empty; }
}
EOF

cat > 0/p << 'EOF'
FoamFile { version 2.0; format ascii; class volScalarField; object p; }
dimensions [0 2 -2 0 0 0 0];
internalField uniform 0;
boundaryField
{
    movingWall { type zeroGradient; }
    fixedWalls { type zeroGradient; }
    frontAndBack { type empty; }
}
EOF

cat > system/controlDict << 'EOF'
FoamFile { version 2.0; format ascii; class dictionary; object controlDict; }
application     simpleHIPFoam;
startFrom       startTime;
startTime       0;
stopAt          endTime;
endTime         10;
deltaT          1;
writeControl    timeStep;
writeInterval   10;
purgeWrite      0;
writeFormat     ascii;
writePrecision  6;
writeCompression off;
timeFormat      general;
timePrecision   6;
runTimeModifiable true;
EOF

cat > system/fvSchemes << 'EOF'
FoamFile { version 2.0; format ascii; class dictionary; object fvSchemes; }
ddtSchemes { default steadyState; }
gradSchemes { default Gauss linear; }
divSchemes { default none; div(phi,U) bounded Gauss linearUpwind grad(U); }
laplacianSchemes { default Gauss linear corrected; }
interpolationSchemes { default linear; }
snGradSchemes { default corrected; }
EOF

cat > system/fvSolution << 'EOF'
FoamFile { version 2.0; format ascii; class dictionary; object fvSolution; }
solvers
{
    p { solver PCG; preconditioner DIC; tolerance 1e-06; relTol 0.05; }
    U { solver PBiCGStab; preconditioner DILU; tolerance 1e-05; relTol 0.1; }
}
SIMPLE
{
    nNonOrthogonalCorrectors 0;
    consistent yes;
    useHIPSolver false;
    hipSolver { maxIter 1000; tolerance 1e-6; }
    residualControl { p 1e-5; U 1e-5; }
}
relaxationFactors { equations { U 0.9; ".*" 0.9; } fields { p 0.3; } }
EOF

cat > constant/transportProperties << 'EOF'
FoamFile { version 2.0; format ascii; class dictionary; object transportProperties; }
transportModel Newtonian;
nu [0 2 -1 0 0 0 0] 1e-05;
EOF

cat > constant/turbulenceProperties << 'EOF'
FoamFile { version 2.0; format ascii; class dictionary; object turbulenceProperties; }
simulationType laminar;
EOF

# Test run
echo "Testing simpleHIPFoam..."
simpleHIPFoam > /dev/null 2>&1

if [ $? -eq 0 ]; then
    echo "✓ simpleHIPFoam test passed!"
else
    echo "✗ simpleHIPFoam test failed"
    exit 1
fi

cd - > /dev/null
EOFBENCH

chmod +x benchmark.sh
./benchmark.sh

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Installation test passed!${NC}"
else
    echo -e "${YELLOW}⚠ Installation test had issues${NC}"
fi

# Summary
echo ""
echo -e "${CYAN}╔═══════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║                                           ║${NC}"
echo -e "${CYAN}║     Installation Complete! 🚀             ║${NC}"
echo -e "${CYAN}║                                           ║${NC}"
echo -e "${CYAN}╚═══════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}simpleHIPFoam is ready to use!${NC}"
echo ""
echo -e "${YELLOW}Quick Start:${NC}"
echo ""
echo "1. Go to your OpenFOAM case directory:"
echo "   cd /path/to/your/case"
echo ""
echo "2. Add GPU settings to system/fvSolution:"
echo "   (see QUICKSTART.md for details)"
echo ""
echo "3. Run simpleHIPFoam:"
echo "   simpleHIPFoam"
echo ""
echo "4. Or run full benchmark:"
echo "   cp $(pwd)/benchmark.sh /path/to/your/case/"
echo "   cd /path/to/your/case"
echo "   ./benchmark.sh"
echo ""
echo -e "${BLUE}Documentation:${NC}"
echo "  - Quick start: QUICKSTART.md"
echo "  - Full guide:  doc/userGuide.md"
echo ""
echo -e "${BLUE}GPU Info:${NC}"
if command -v rocm-smi &> /dev/null; then
    rocm-smi --showproductname 2>/dev/null | grep -E "Card|GPU" | head -3
else
    echo "  Run 'rocm-smi' to check GPU status"
fi
echo ""