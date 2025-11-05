#!/bin/bash
# Diagnose OpenFOAM installation issues

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=========================================="
echo "  OpenFOAM Diagnostic Tool"
echo -e "==========================================${NC}\n"

OPENFOAM_DIR="/usr/lib/openfoam/openfoam2412"

echo -e "${BLUE}[1] Checking directory structure...${NC}"
echo ""

# Check key directories
dirs_to_check=(
    "src"
    "src/finiteVolume"
    "src/finiteVolume/lnInclude"
    "src/OpenFOAM"
    "src/OpenFOAM/lnInclude"
    "applications"
    "tutorials"
    "etc"
)

for dir in "${dirs_to_check[@]}"; do
    full_path="$OPENFOAM_DIR/$dir"
    if [ -d "$full_path" ]; then
        count=$(find "$full_path" -maxdepth 1 -type f 2>/dev/null | wc -l)
        echo -e "  ${GREEN}✓${NC} $dir (${count} files)"
    else
        echo -e "  ${RED}✗${NC} $dir (MISSING)"
    fi
done

echo ""
echo -e "${BLUE}[2] Searching for fvCFD.H...${NC}"
echo ""

# Search for fvCFD.H
if [ -f "$OPENFOAM_DIR/src/finiteVolume/lnInclude/fvCFD.H" ]; then
    echo -e "  ${GREEN}✓ Found: $OPENFOAM_DIR/src/finiteVolume/lnInclude/fvCFD.H${NC}"
else
    echo -e "  ${RED}✗ NOT FOUND at expected location${NC}"
    echo ""
    echo "  Searching entire OpenFOAM directory..."
    find "$OPENFOAM_DIR" -name "fvCFD.H" 2>/dev/null | while read file; do
        echo -e "    ${YELLOW}Found at: $file${NC}"
    done
    
    if [ -z "$(find "$OPENFOAM_DIR" -name "fvCFD.H" 2>/dev/null)" ]; then
        echo -e "    ${RED}fvCFD.H not found anywhere!${NC}"
    fi
fi

echo ""
echo -e "${BLUE}[3] Checking if lnInclude directories are populated...${NC}"
echo ""

# Check lnInclude directories
lninclude_dirs=$(find "$OPENFOAM_DIR/src" -type d -name "lnInclude" 2>/dev/null)

if [ -z "$lninclude_dirs" ]; then
    echo -e "  ${RED}✗ No lnInclude directories found!${NC}"
    echo ""
    echo -e "  ${YELLOW}This is the problem!${NC}"
    echo ""
    echo "  The 'lnInclude' directories contain symbolic links to header files."
    echo "  They should be created during OpenFOAM compilation/installation."
    echo ""
    echo -e "  ${BLUE}Solution: Rebuild lnInclude directories${NC}"
    echo ""
    echo "  Run these commands:"
    echo ""
    echo "    cd $OPENFOAM_DIR"
    echo "    source etc/bashrc"
    echo "    wmakeLnInclude -u src/OpenFOAM"
    echo "    wmakeLnInclude -u src/finiteVolume"
    echo "    wmakeLnInclude -u src/meshTools"
    echo ""
else
    total_count=0
    empty_count=0
    
    while IFS= read -r dir; do
        count=$(find "$dir" -maxdepth 1 -type l 2>/dev/null | wc -l)
        total_count=$((total_count + count))
        
        if [ $count -eq 0 ]; then
            empty_count=$((empty_count + 1))
            echo -e "  ${RED}✗${NC} $dir (empty!)"
        else
            echo -e "  ${GREEN}✓${NC} $dir (${count} links)"
        fi
    done <<< "$lninclude_dirs"
    
    echo ""
    echo "  Total lnInclude directories: $(echo "$lninclude_dirs" | wc -l)"
    echo "  Total header links: $total_count"
    echo "  Empty directories: $empty_count"
    
    if [ $empty_count -gt 0 ]; then
        echo ""
        echo -e "  ${YELLOW}Some lnInclude directories are empty!${NC}"
        echo -e "  ${BLUE}Need to rebuild them.${NC}"
    fi
fi

echo ""
echo -e "${BLUE}[4] Checking OpenFOAM environment variables...${NC}"
echo ""

source "$OPENFOAM_DIR/etc/bashrc" 2>/dev/null

if [ -n "$WM_PROJECT_DIR" ]; then
    echo -e "  ${GREEN}✓${NC} WM_PROJECT_DIR: $WM_PROJECT_DIR"
else
    echo -e "  ${RED}✗${NC} WM_PROJECT_DIR not set"
fi

if [ -n "$FOAM_SRC" ]; then
    echo -e "  ${GREEN}✓${NC} FOAM_SRC: $FOAM_SRC"
    
    # Check if FOAM_SRC actually exists
    if [ -d "$FOAM_SRC" ]; then
        echo -e "      ${GREEN}✓${NC} Directory exists"
    else
        echo -e "      ${RED}✗${NC} Directory does NOT exist!"
    fi
else
    echo -e "  ${RED}✗${NC} FOAM_SRC not set"
fi

if [ -n "$FOAM_APPBIN" ]; then
    echo -e "  ${GREEN}✓${NC} FOAM_APPBIN: $FOAM_APPBIN"
else
    echo -e "  ${RED}✗${NC} FOAM_APPBIN not set"
fi

echo ""
echo -e "${BLUE}[5] Checking wmake availability...${NC}"
echo ""

if command -v wmake &> /dev/null; then
    echo -e "  ${GREEN}✓${NC} wmake found: $(which wmake)"
    wmake -help 2>&1 | head -3
else
    echo -e "  ${RED}✗${NC} wmake not found in PATH"
fi

echo ""
echo -e "${BLUE}=========================================="
echo "  Diagnosis Complete"
echo -e "==========================================${NC}\n"

# Determine the issue and provide solution
if [ ! -d "$OPENFOAM_DIR/src/finiteVolume/lnInclude" ] || [ -z "$(find "$OPENFOAM_DIR/src/finiteVolume/lnInclude" -maxdepth 1 -type l 2>/dev/null)" ]; then
    echo -e "${YELLOW}ISSUE IDENTIFIED: lnInclude directories are missing or empty${NC}"
    echo ""
    echo "The OpenFOAM development headers (symbolic links) need to be created."
    echo ""
    echo -e "${GREEN}SOLUTION:${NC}"
    echo ""
    echo "Run this command to fix it:"
    echo ""
    cat > fix_openfoam_lninclude.sh << 'FIXEOF'
#!/bin/bash
# Fix OpenFOAM lnInclude directories

set -e

OPENFOAM_DIR="/usr/lib/openfoam/openfoam2412"

echo "Fixing OpenFOAM lnInclude directories..."
echo ""

# Source OpenFOAM
source "$OPENFOAM_DIR/etc/bashrc"

# Key directories that need lnInclude
dirs=(
    "OpenFOAM"
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

cd "$FOAM_SRC"

for dir in "${dirs[@]}"; do
    if [ -d "$dir" ]; then
        echo "Processing: $dir"
        wmakeLnInclude -u "$dir"
    fi
done

echo ""
echo "Checking results..."
if [ -f "finiteVolume/lnInclude/fvCFD.H" ]; then
    echo "✓ fvCFD.H created successfully!"
    echo ""
    echo "OpenFOAM development environment is now ready!"
else
    echo "✗ Still having issues. The source package may be incomplete."
    echo ""
    echo "Try reinstalling the source package:"
    echo "  sudo apt-get install --reinstall openfoam2412-source openfoam2412-dev"
fi
FIXEOF
    
    chmod +x fix_openfoam_lninclude.sh
    
    echo "./fix_openfoam_lninclude.sh"
    echo ""
    echo -e "${BLUE}I created 'fix_openfoam_lninclude.sh' for you.${NC}"
    echo "Run: ./fix_openfoam_lninclude.sh"
    echo ""
else
    echo -e "${GREEN}OpenFOAM looks properly configured!${NC}"
    echo ""
    echo "If you're still having build issues, try:"
    echo ""
    echo "  source $OPENFOAM_DIR/etc/bashrc"
    echo "  ./Allwmake"
fi