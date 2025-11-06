#!/bin/bash
# Install OpenFOAM v2412 properly with all development files

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}=========================================="
echo "  OpenFOAM v2412 Proper Installation"
echo -e "==========================================${NC}\n"

echo "This script will ensure OpenFOAM v2412 is properly installed"
echo "with all necessary development files."
echo ""

# Check if already installed
if [ -d "/usr/lib/openfoam/openfoam2412/src/finiteVolume/lnInclude" ]; then
    if [ -f "/usr/lib/openfoam/openfoam2412/src/finiteVolume/lnInclude/fvCFD.H" ]; then
        echo -e "${GREEN}OpenFOAM appears to be properly installed!${NC}"
        echo ""
        read -p "Reinstall anyway? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Skipping installation. Run ./fix_and_build.sh to build."
            exit 0
        fi
    fi
fi

echo -e "${BLUE}[1/4] Checking system...${NC}"

# Check Ubuntu version
if [ -f /etc/os-release ]; then
    . /etc/os-release
    echo "  OS: $NAME $VERSION"
    
    # Warn if not Ubuntu
    if [[ ! "$ID" =~ ubuntu|debian ]]; then
        echo -e "${YELLOW}  Warning: Not Ubuntu/Debian. Installation may differ.${NC}"
    fi
else
    echo -e "${YELLOW}  Warning: Cannot determine OS${NC}"
fi

# Check for sudo
if ! sudo -v; then
    echo -e "${RED}ERROR: Need sudo access${NC}"
    exit 1
fi

echo ""
echo -e "${BLUE}[2/4] Adding OpenFOAM repository...${NC}"

# Add OpenFOAM.com repository
if [ ! -f /etc/apt/sources.list.d/openfoam.list ]; then
    echo "  Adding repository..."
    
    # Add repository key and source
    sudo sh -c "curl -s https://dl.openfoam.com/add-debian-repo.sh | bash"
    
    echo -e "${GREEN}  ✓ Repository added${NC}"
else
    echo -e "${GREEN}  ✓ Repository already added${NC}"
fi

echo ""
echo -e "${BLUE}[3/4] Installing OpenFOAM packages...${NC}"

# Update package list
echo "  Updating package list..."
sudo apt-get update -qq

# Install all necessary packages
echo "  Installing OpenFOAM v2412..."
sudo apt-get install -y \
    openfoam2412-default \
    openfoam2412-dev \
    openfoam2412-source \
    openfoam2412-doc

echo -e "${GREEN}  ✓ Packages installed${NC}"

echo ""
echo -e "${BLUE}[4/4] Building lnInclude directories...${NC}"

# Source OpenFOAM
source /usr/lib/openfoam/openfoam2412/etc/bashrc

# Build lnInclude for critical directories
cd "$FOAM_SRC"

DIRS=(
    "OpenFOAM"
    "OSspecific/POSIX"
    "finiteVolume"
    "meshTools"
    "sampling"
    "TurbulenceModels/turbulenceModels"
    "TurbulenceModels/incompressible"
    "transportModels"
    "transportModels/incompressible/singlePhaseTransportModel"
    "dynamicMesh"
    "dynamicFvMesh"
)

for dir in "${DIRS[@]}"; do
    if [ -d "$dir" ]; then
        echo "  Building lnInclude for: $dir"
        wmakeLnInclude "$dir" 2>/dev/null || true
    fi
done

# Verify installation
echo ""
echo -e "${BLUE}Verifying installation...${NC}"

if [ -f "$FOAM_SRC/finiteVolume/lnInclude/fvCFD.H" ]; then
    echo -e "${GREEN}✓ fvCFD.H found${NC}"
else
    echo -e "${RED}✗ fvCFD.H still not found!${NC}"
    echo ""
    echo "Installation may have issues. Checking what we have..."
    echo ""
    
    # Search for fvCFD.H
    echo "Searching for fvCFD.H..."
    find /usr/lib/openfoam/openfoam2412 -name "fvCFD.H" 2>/dev/null | while read file; do
        echo "  Found: $file"
        
        # If found, try to link it
        if [[ "$file" == *"/finiteVolume/"* ]]; then
            dir=$(dirname "$file")
            if [ ! -d "$dir/../lnInclude" ]; then
                mkdir -p "$dir/../lnInclude"
            fi
            ln -sf "$file" "$dir/../lnInclude/" 2>/dev/null || true
        fi
    done
    
    if [ ! -f "$FOAM_SRC/finiteVolume/lnInclude/fvCFD.H" ]; then
        echo ""
        echo -e "${RED}ERROR: Cannot create proper OpenFOAM development environment${NC}"
        echo ""
        echo "The package installation may be incomplete."
        echo ""
        echo -e "${YELLOW}Alternative: Build from source${NC}"
        echo "This takes ~2 hours but guarantees everything works:"
        echo ""
        echo "  mkdir -p ~/OpenFOAM"
        echo "  cd ~/OpenFOAM"
        echo "  wget https://dl.openfoam.com/source/v2412/OpenFOAM-v2412.tgz"
        echo "  tar -xzf OpenFOAM-v2412.tgz"
        echo "  cd OpenFOAM-v2412"
        echo "  source etc/bashrc"
        echo "  ./Allwmake -j -s -q"
        echo ""
        exit 1
    fi
fi

# Check other critical headers
HEADERS=(
    "$FOAM_SRC/OpenFOAM/lnInclude/lduMatrix.H"
    "$FOAM_SRC/finiteVolume/lnInclude/fvMesh.H"
    "$FOAM_SRC/finiteVolume/lnInclude/volFields.H"
)

for header in "${HEADERS[@]}"; do
    if [ -f "$header" ]; then
        echo -e "${GREEN}✓ $(basename $header)${NC}"
    else
        echo -e "${YELLOW}⚠ $(basename $header) not found${NC}"
    fi
done

echo ""
echo -e "${GREEN}=========================================="
echo "  OpenFOAM Installation Complete!"
echo -e "==========================================${NC}"
echo ""
echo "OpenFOAM is now properly installed with development files."
echo ""
echo "To use it, add this to your ~/.bashrc:"
echo ""
echo "  source /usr/lib/openfoam/openfoam2412/etc/bashrc"
echo ""
echo "Or run it now:"
echo ""
echo "  source /usr/lib/openfoam/openfoam2412/etc/bashrc"
echo ""
echo "Then build simpleHIPFoam:"
echo ""
echo "  ./fix_and_build.sh"
echo ""