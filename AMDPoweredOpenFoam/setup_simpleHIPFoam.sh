#!/bin/bash
# setup_simpleHIPFoam.sh
# Script to reorganize MyCFD into proper simpleHIPFoam structure

set -e  # Exit on error

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${CYAN}================================================${NC}"
echo -e "${CYAN}   simpleHIPFoam Project Setup${NC}"
echo -e "${CYAN}================================================${NC}\n"

# Check we're in MyCFD directory
if [ ! -f "LICENSE" ]; then
    echo -e "${YELLOW}Warning: LICENSE not found. Are you in MyCFD directory?${NC}"
    read -p "Continue anyway? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

echo -e "${GREEN}Creating directory structure...${NC}"

# Create main directories
mkdir -p applications/solvers/simpleHIPFoam/hipSolver
mkdir -p applications/solvers/simpleHIPFoam/Make
mkdir -p src/hipAcceleration/hipLinearSolvers
mkdir -p src/hipAcceleration/hipPreconditioners
mkdir -p tutorials/incompressible/simpleHIPFoam/cavity/{0,constant,system}
mkdir -p tutorials/incompressible/simpleHIPFoam/pitzDaily
mkdir -p benchmarks/results
mkdir -p doc/images
mkdir -p scripts
mkdir -p tests

echo -e "${GREEN}Moving old example files...${NC}"

# Archive old files
mkdir -p archive/old_examples
if [ -f "main.cpp" ]; then
    mv main.cpp archive/old_examples/
fi
if [ -f "matmul_hip.cpp" ]; then
    mv matmul_hip.cpp archive/old_examples/
fi
if [ -d "solvers" ]; then
    mv solvers archive/old_examples/
fi
if [ -d "include" ]; then
    mv include archive/old_examples/
fi
if [ -f "Makefile" ]; then
    mv Makefile archive/old_examples/
fi
if [ -f "config.json" ]; then
    rm config.json  # Empty file
fi

echo -e "${GREEN}Creating placeholder files...${NC}"

# Create .gitkeep for empty directories
touch benchmarks/results/.gitkeep
touch tests/.gitkeep
touch doc/images/.gitkeep

# Create Allwmake master build script
cat > Allwmake << 'EOF'
#!/bin/sh
cd "${0%/*}" || exit
. ${WM_PROJECT_DIR:?}/wmake/scripts/AllwmakeParseArguments

echo "Building simpleHIPFoam project..."

# Build libraries first
echo "Building HIP acceleration libraries..."
wmake $targetType src/hipAcceleration

# Build solver
echo "Building simpleHIPFoam solver..."
wmake $targetType applications/solvers/simpleHIPFoam

echo "Build complete!"
EOF
chmod +x Allwmake

# Create Allclean script
cat > Allclean << 'EOF'
#!/bin/sh
cd "${0%/*}" || exit
. ${WM_PROJECT_DIR:?}/wmake/scripts/AllwmakeParseArguments

echo "Cleaning simpleHIPFoam project..."

wclean src/hipAcceleration
wclean applications/solvers/simpleHIPFoam

echo "Clean complete!"
EOF
chmod +x Allclean

# Create build script
cat > scripts/build.sh << 'EOF'
#!/bin/bash
# Build script for simpleHIPFoam

source ${WM_PROJECT_DIR}/etc/bashrc

echo "Checking ROCm installation..."
if ! command -v hipcc &> /dev/null; then
    echo "ERROR: hipcc not found. Please install ROCm."
    exit 1
fi

echo "ROCm version:"
hipcc --version

echo ""
echo "Building simpleHIPFoam..."
cd "$(dirname "$0")/.."
./Allwmake
EOF
chmod +x scripts/build.sh

# Create setup script for environment
cat > scripts/setup.sh << 'EOF'
#!/bin/bash
# Environment setup for simpleHIPFoam development

# Source OpenFOAM
if [ -f /opt/openfoam2412/etc/bashrc ]; then
    source /opt/openfoam2412/etc/bashrc
    echo "OpenFOAM v2412 environment loaded"
elif [ -f $HOME/OpenFOAM/OpenFOAM-v2412/etc/bashrc ]; then
    source $HOME/OpenFOAM/OpenFOAM-v2412/etc/bashrc
    echo "OpenFOAM v2412 environment loaded"
else
    echo "ERROR: OpenFOAM v2412 not found!"
    echo "Please install OpenFOAM v2412 or update this script"
    return 1
fi

# Setup ROCm
export ROCM_PATH=/opt/rocm
export PATH=$ROCM_PATH/bin:$PATH
export LD_LIBRARY_PATH=$ROCM_PATH/lib:$LD_LIBRARY_PATH

echo "ROCm path: $ROCM_PATH"

# Check GPU
if command -v rocm-smi &> /dev/null; then
    echo ""
    echo "Available AMD GPUs:"
    rocm-smi --showproductname
else
    echo "WARNING: rocm-smi not found"
fi

echo ""
echo "Environment ready! Run './Allwmake' to build."
EOF
chmod +x scripts/setup.sh

# Create test script
cat > scripts/test.sh << 'EOF'
#!/bin/bash
# Run test cases for simpleHIPFoam

cd tutorials/incompressible/simpleHIPFoam/cavity
echo "Running cavity test case..."
./Allrun

cd ../../../../
echo "All tests complete!"
EOF
chmod +x scripts/test.sh

# Create main README if it doesn't exist
if [ ! -f "README.md" ]; then
    cat > README.md << 'EOF'
# simpleHIPFoam

HIP/ROCm-accelerated steady-state incompressible flow solver for OpenFOAM v2412.

## Quick Start

```bash
# Setup environment
source scripts/setup.sh

# Build
./Allwmake

# Run test case
cd tutorials/incompressible/simpleHIPFoam/cavity
./Allrun
```

See `doc/userGuide.md` for detailed documentation.
EOF
fi

echo -e "\n${GREEN}Creating documentation templates...${NC}"

cat > doc/userGuide.md << 'EOF'
# simpleHIPFoam User Guide

## Installation
See main README.md

## Running Cases
[To be filled]

## Configuration
[To be filled]

## Troubleshooting
[To be filled]
EOF

cat > doc/developerGuide.md << 'EOF'
# simpleHIPFoam Developer Guide

## Architecture
[To be filled]

## Adding New Solvers
[To be filled]

## Contributing
[To be filled]
EOF

cat > doc/theory.md << 'EOF'
# Theory and Algorithms

## SIMPLE Algorithm
[To be filled]

## HIP Acceleration Strategy
[To be filled]

## Matrix Formats
[To be filled]
EOF

echo -e "\n${CYAN}================================================${NC}"
echo -e "${GREEN}Setup complete!${NC}"
echo -e "${CYAN}================================================${NC}\n"

echo "Directory structure created:"
echo "  applications/     - Solver applications"
echo "  src/              - Shared libraries"
echo "  tutorials/        - Test cases"
echo "  benchmarks/       - Performance tests"
echo "  doc/              - Documentation"
echo "  scripts/          - Utility scripts"
echo ""
echo "Old files archived to: archive/old_examples/"
echo ""
echo "Next steps:"
echo "  1. Place solver source files in applications/solvers/simpleHIPFoam/"
echo "  2. Run: source scripts/setup.sh"
echo "  3. Run: ./Allwmake"
echo ""
echo -e "${YELLOW}Note: You still need to create the actual source files!${NC}"
echo "      Use the artifacts I provided earlier."