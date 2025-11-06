#!/bin/bash
# Fix missing symlinks in OpenFOAM lnInclude directories

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=========================================="
echo "  Fixing OpenFOAM lnInclude Directories"
echo -e "==========================================${NC}\n"

FOAM_SRC="/home/indigo/OpenFOAM/OpenFOAM-v2412/src"

if [ ! -d "$FOAM_SRC" ]; then
    echo -e "${RED}ERROR: OpenFOAM src not found at $FOAM_SRC${NC}"
    exit 1
fi

cd "$FOAM_SRC"

echo "Checking for missing headers..."

# List of critical headers that need to be in lnInclude
CRITICAL_HEADERS=(
    "OpenFOAM/db/IOstreams/IOstreams/ISstream.H"
    "OpenFOAM/fields/FieldFields/FieldField/FieldField.H"
    "OpenFOAM/containers/Lists/PtrDynList/PtrDynList.H"
    "OpenFOAM/db/Time/TimeState.H"
    "OpenFOAM/global/profiling/profiling.H"
)

MISSING_COUNT=0

for header in "${CRITICAL_HEADERS[@]}"; do
    if [ -f "$header" ]; then
        # Extract directory and filename
        dir=$(dirname "$header")
        file=$(basename "$header")
        base_dir=$(echo "$header" | cut -d'/' -f1)
        
        # Check if symlink exists in lnInclude
        if [ ! -f "$base_dir/lnInclude/$file" ]; then
            echo -e "  ${BLUE}Linking: $file${NC}"
            
            # Calculate relative path from lnInclude to actual file
            rel_path=$(realpath --relative-to="$base_dir/lnInclude" "$header")
            
            # Create symlink
            ln -sf "$rel_path" "$base_dir/lnInclude/$file"
            
            ((MISSING_COUNT++))
        else
            echo -e "  ${GREEN}✓${NC} $file already linked"
        fi
    else
        echo -e "  ${RED}✗${NC} $header not found in source tree!"
    fi
done

echo ""
if [ $MISSING_COUNT -gt 0 ]; then
    echo -e "${GREEN}✓ Fixed $MISSING_COUNT missing symlinks${NC}"
else
    echo -e "${GREEN}✓ All symlinks already present${NC}"
fi

echo ""
echo "Verifying critical headers are now accessible..."

cd "$FOAM_SRC/OpenFOAM/lnInclude"

VERIFY_HEADERS=(
    "ISstream.H"
    "FieldField.H"
    "PtrDynList.H"
    "profiling.H"
)

ALL_OK=true
for header in "${VERIFY_HEADERS[@]}"; do
    if [ -f "$header" ]; then
        echo -e "  ${GREEN}✓${NC} $header"
    else
        echo -e "  ${RED}✗${NC} $header MISSING"
        ALL_OK=false
    fi
done

echo ""
if [ "$ALL_OK" = true ]; then
    echo -e "${GREEN}=========================================="
    echo "  All headers fixed!"
    echo -e "==========================================${NC}"
    echo ""
    echo "Now run: ./MANUAL_BUILD.sh"
else
    echo -e "${RED}=========================================="
    echo "  Some headers still missing"
    echo -e "==========================================${NC}"
    echo ""
    echo "Your OpenFOAM installation may be incomplete."
    echo ""
    echo "Trying comprehensive fix..."
    
    # Nuclear option: rebuild ALL lnInclude directories
    cd "$FOAM_SRC/OpenFOAM"
    
    echo ""
    echo "Rebuilding OpenFOAM/lnInclude from scratch..."
    rm -rf lnInclude
    mkdir -p lnInclude
    
    # Find all .H files and link them
    find . -maxdepth 5 -name "*.H" -type f | while read file; do
        base=$(basename "$file")
        if [ ! -f "lnInclude/$base" ]; then
            rel=$(realpath --relative-to="lnInclude" "$file")
            ln -sf "$rel" "lnInclude/$base" 2>/dev/null || true
        fi
    done
    
    echo "  Created $(ls lnInclude/*.H 2>/dev/null | wc -l) symlinks"
    
    # Verify again
    echo ""
    echo "Re-verifying..."
    cd lnInclude
    for header in "${VERIFY_HEADERS[@]}"; do
        if [ -f "$header" ]; then
            echo -e "  ${GREEN}✓${NC} $header"
        else
            echo -e "  ${RED}✗${NC} $header STILL MISSING"
        fi
    done
fi