#!/bin/bash
# Check OpenFOAM installation and install if needed

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}=========================================="
echo "  OpenFOAM Installation Checker"
echo -e "==========================================${NC}\n"

# Check what's installed
echo -e "${BLUE}[1] Checking current OpenFOAM installation...${NC}"

if [ -d "/usr/lib/openfoam/openfoam2412" ]; then
    echo -e "${GREEN}✓ OpenFOAM directory found: /usr/lib/openfoam/openfoam2412${NC}"
    
    # Check for bashrc
    if [ -f "/usr/lib/openfoam/openfoam2412/etc/bashrc" ]; then
        echo -e "${GREEN}✓ bashrc found${NC}"
    else
        echo -e "${RED}✗ bashrc NOT found${NC}"
    fi
    
    # Check for source files
    if [ -d "/usr/lib/openfoam/openfoam2412/src" ]; then
        echo -e "${GREEN}✓ src/ directory exists${NC}"
    else
        echo -e "${RED}✗ src/ directory NOT found - this is the problem!${NC}"
    fi
else
    echo -e "${RED}✗ OpenFOAM not found at /usr/lib/openfoam/openfoam2412${NC}"
fi

echo ""
echo -e "${BLUE}[2] Checking for OpenFOAM packages...${NC}"

# Check installed packages
if dpkg -l | grep -q "openfoam2412"; then
    echo -e "${GREEN}✓ OpenFOAM packages installed:${NC}"
    dpkg -l | grep openfoam2412
else
    echo -e "${RED}✗ No OpenFOAM packages found${NC}"
fi

echo ""
echo -e "${BLUE}[3] Searching for OpenFOAM installations...${NC}"

# Search for OpenFOAM installations
OPENFOAM_LOCATIONS=(
    "/opt/openfoam2412"
    "/usr/lib/openfoam/openfoam2412"
    "$HOME/OpenFOAM/OpenFOAM-v2412"
    "/opt/OpenFOAM/OpenFOAM-v2412"
)

FOUND_VALID=""
for loc in "${OPENFOAM_LOCATIONS[@]}"; do
    if [ -d "$loc" ]; then
        echo -e "  Found: $loc"
        if [ -f "$loc/etc/bashrc" ]; then
            echo -e "    ${GREEN}✓ Has bashrc${NC}"
            if [ -d "$loc/src" ]; then
                echo -e "    ${GREEN}✓ Has src/ directory${NC}"
                FOUND_VALID="$loc"
            else
                echo -e "    ${RED}✗ Missing src/ directory${NC}"
            fi
        fi
    fi
done

echo ""
if [ -z "$FOUND_VALID" ]; then
    echo -e "${RED}=========================================="
    echo "  No valid OpenFOAM installation found!"
    echo -e "==========================================${NC}\n"
    
    echo -e "${YELLOW}You need to install OpenFOAM v2412 with source files.${NC}"
    echo ""
    echo "Installation options:"
    echo ""
    echo -e "${CYAN}Option 1: Install from OpenFOAM.com (Recommended)${NC}"
    echo "  This includes all source files needed for development."
    echo ""
    echo "  Commands:"
    echo "    # Add repository"
    echo "    curl https://dl.openfoam.com/add-debian-repo.sh | sudo bash"
    echo ""
    echo "    # Install OpenFOAM"
    echo "    sudo apt-get update"
    echo "    sudo apt-get install openfoam2412-default"
    echo ""
    echo "    # This installs to: /usr/lib/openfoam/openfoam2412/"
    echo ""
    echo -e "${CYAN}Option 2: Build from source (Advanced)${NC}"
    echo "  Takes 2-4 hours but gives you full control."
    echo ""
    echo "  # Download source"
    echo "  wget https://dl.openfoam.com/source/v2412/OpenFOAM-v2412.tgz"
    echo "  tar -xzf OpenFOAM-v2412.tgz"
    echo "  cd OpenFOAM-v2412"
    echo ""
    echo "  # Install dependencies"
    echo "  sudo apt-get install build-essential cmake git ca-certificates \\"
    echo "    flex libfl-dev bison zlib1g-dev libboost-system-dev \\"
    echo "    libboost-thread-dev libopenmpi-dev openmpi-bin gnuplot \\"
    echo "    libreadline-dev libncurses-dev libxt-dev libscotch-dev \\"
    echo "    libcgal-dev libgmp-dev libmpfr-dev"
    echo ""
    echo "  # Build"
    echo "  source etc/bashrc"
    echo "  ./Allwmake -j -s -q -l"
    echo ""
    echo "Would you like me to:"
    echo "  1) Install OpenFOAM from repository (requires sudo)"
    echo "  2) Just show instructions (manual install)"
    echo "  3) Exit"
    echo ""
    read -p "Choice (1/2/3): " choice
    
    case $choice in
        1)
            echo ""
            echo -e "${CYAN}Installing OpenFOAM v2412...${NC}"
            echo ""
            
            # Check for sudo
            if ! sudo -v; then
                echo -e "${RED}ERROR: Need sudo access to install${NC}"
                exit 1
            fi
            
            # Add repository
            echo "Adding OpenFOAM repository..."
            curl -s https://dl.openfoam.com/add-debian-repo.sh | sudo bash
            
            # Update
            echo "Updating package list..."
            sudo apt-get update
            
            # Install
            echo "Installing OpenFOAM v2412 (this may take 5-10 minutes)..."
            sudo apt-get install -y openfoam2412-default
            
            echo ""
            echo -e "${GREEN}=========================================="
            echo "  OpenFOAM Installation Complete!"
            echo -e "==========================================${NC}\n"
            
            FOUND_VALID="/usr/lib/openfoam/openfoam2412"
            ;;
        2)
            echo ""
            echo "Please install OpenFOAM manually using the instructions above."
            echo "Then re-run this script."
            exit 0
            ;;
        *)
            echo "Exiting..."
            exit 0
            ;;
    esac
else
    echo -e "${GREEN}=========================================="
    echo "  Valid OpenFOAM installation found!"
    echo -e "==========================================${NC}"
    echo ""
    echo "Location: $FOUND_VALID"
fi

# Now verify it works
echo ""
echo -e "${BLUE}[4] Verifying OpenFOAM environment...${NC}"

# Source OpenFOAM
if [ -f "$FOUND_VALID/etc/bashrc" ]; then
    echo "Sourcing: $FOUND_VALID/etc/bashrc"
    source "$FOUND_VALID/etc/bashrc"
    
    echo ""
    echo -e "${GREEN}Environment variables set:${NC}"
    echo "  WM_PROJECT_DIR: $WM_PROJECT_DIR"
    echo "  WM_PROJECT_VERSION: $WM_PROJECT_VERSION"
    echo "  FOAM_SRC: $FOAM_SRC"
    echo "  FOAM_APPBIN: $FOAM_APPBIN"
    
    # Check critical files
    echo ""
    echo -e "${BLUE}Checking critical include files...${NC}"
    
    if [ -f "$FOAM_SRC/finiteVolume/lnInclude/fvCFD.H" ]; then
        echo -e "${GREEN}✓ fvCFD.H found${NC}"
    else
        echo -e "${RED}✗ fvCFD.H NOT found at $FOAM_SRC/finiteVolume/lnInclude/${NC}"
    fi
    
    if [ -f "$FOAM_SRC/OpenFOAM/lnInclude/lduMatrix.H" ]; then
        echo -e "${GREEN}✓ lduMatrix.H found${NC}"
    else
        echo -e "${RED}✗ lduMatrix.H NOT found${NC}"
    fi
    
    # Check wmake
    if command -v wmake &> /dev/null; then
        echo -e "${GREEN}✓ wmake available${NC}"
    else
        echo -e "${RED}✗ wmake NOT available${NC}"
    fi
    
    echo ""
    echo -e "${GREEN}=========================================="
    echo "  OpenFOAM is ready!"
    echo -e "==========================================${NC}\n"
    
    echo "To use OpenFOAM in your shell, add this to ~/.bashrc:"
    echo ""
    echo "  source $FOUND_VALID/etc/bashrc"
    echo ""
    echo "Or run it now:"
    echo ""
    echo "  source $FOUND_VALID/etc/bashrc"
    echo ""
    
    # Create convenience script
    cat > load_openfoam.sh << EOF
#!/bin/bash
# Load OpenFOAM environment
source $FOUND_VALID/etc/bashrc

# Load ROCm
export ROCM_PATH=/opt/rocm
export PATH=\$ROCM_PATH/bin:\$PATH
export LD_LIBRARY_PATH=\$ROCM_PATH/lib:\$LD_LIBRARY_PATH

echo "OpenFOAM v2412 environment loaded"
echo "ROCm environment loaded"
echo ""
echo "Ready to build simpleHIPFoam!"
echo "Run: ./Allwmake"
EOF
    
    chmod +x load_openfoam.sh
    
    echo -e "${CYAN}I created 'load_openfoam.sh' for you.${NC}"
    echo "Run: source load_openfoam.sh"
    echo "Then: ./Allwmake"
    
else
    echo -e "${RED}ERROR: Could not source OpenFOAM environment${NC}"
    exit 1
fi