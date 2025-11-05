#!/bin/bash
# benchmark.sh - Compare simpleFoam vs simpleHIPFoam performance

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}  simpleFoam vs simpleHIPFoam Benchmark${NC}"
echo -e "${CYAN}========================================${NC}\n"

# Check if we're in a case directory
if [ ! -f "system/controlDict" ]; then
    echo -e "${RED}ERROR: Not in an OpenFOAM case directory!${NC}"
    echo "Please run this script from your case directory"
    exit 1
fi

# Check if solvers exist
if ! command -v simpleFoam &> /dev/null; then
    echo -e "${RED}ERROR: simpleFoam not found!${NC}"
    exit 1
fi

if ! command -v simpleHIPFoam &> /dev/null; then
    echo -e "${RED}ERROR: simpleHIPFoam not found!${NC}"
    echo "Build it first: cd AMDPoweredOpenFoam && ./Allwmake"
    exit 1
fi

# Get number of cells
NCELLS=$(checkMesh -time 0 2>&1 | grep "cells:" | awk '{print $3}')
echo -e "${GREEN}Mesh info:${NC}"
echo "  Cells: $NCELLS"
echo ""

# Create backup of original case
BACKUP_DIR="0.orig"
if [ ! -d "$BACKUP_DIR" ]; then
    echo -e "${YELLOW}Backing up initial conditions...${NC}"
    cp -r 0 $BACKUP_DIR
fi

# Function to run and time a solver
run_solver() {
    local solver=$1
    local use_gpu=$2
    local label=$3
    
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}Running: $label${NC}"
    echo -e "${BLUE}========================================${NC}"
    
    # Clean previous run
    rm -rf [1-9]* processor* log.$solver postProcessing
    cp -r $BACKUP_DIR 0
    
    # Modify fvSolution for GPU if needed
    if [ "$use_gpu" = "true" ]; then
        # Enable HIP solver
        sed -i 's/useHIPSolver[[:space:]]*false/useHIPSolver    true/' system/fvSolution
        echo -e "${GREEN}  GPU acceleration: ENABLED${NC}"
    else
        # Disable HIP solver
        sed -i 's/useHIPSolver[[:space:]]*true/useHIPSolver    false/' system/fvSolution
        echo -e "${YELLOW}  GPU acceleration: DISABLED${NC}"
    fi
    
    # Run solver
    echo ""
    START_TIME=$(date +%s.%N)
    
    $solver > log.$solver 2>&1
    
    END_TIME=$(date +%s.%N)
    ELAPSED=$(echo "$END_TIME - $START_TIME" | bc)
    
    # Extract timing info from log
    EXEC_TIME=$(grep "ExecutionTime" log.$solver | tail -1 | awk '{print $3}')
    CLOCK_TIME=$(grep "ClockTime" log.$solver | tail -1 | awk '{print $3}')
    
    # Extract final residuals
    P_RESIDUAL=$(grep "Solving for p" log.$solver | tail -1 | awk '{print $9}' | tr -d ',')
    U_RESIDUAL=$(grep "Solving for Ux" log.$solver | tail -1 | awk '{print $9}' | tr -d ',')
    
    echo -e "${GREEN}Results:${NC}"
    echo "  Wall time:      ${ELAPSED} s"
    echo "  Execution time: ${EXEC_TIME} s"
    echo "  Clock time:     ${CLOCK_TIME} s"
    echo "  Final p residual: ${P_RESIDUAL}"
    echo "  Final Ux residual: ${U_RESIDUAL}"
    echo ""
    
    # Return execution time for comparison
    echo "$EXEC_TIME"
}

# Run simpleFoam (CPU baseline)
echo ""
CPU_TIME=$(run_solver "simpleFoam" "false" "simpleFoam (CPU)")

# Run simpleHIPFoam without GPU
echo ""
HIP_CPU_TIME=$(run_solver "simpleHIPFoam" "false" "simpleHIPFoam (CPU mode)")

# Run simpleHIPFoam with GPU
echo ""
GPU_TIME=$(run_solver "simpleHIPFoam" "true" "simpleHIPFoam (GPU mode)")

# Restore original fvSolution
git checkout system/fvSolution 2>/dev/null || true

# Calculate speedups
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}  Performance Summary${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""
printf "%-30s %10s\n" "Solver" "Time (s)"
echo "----------------------------------------"
printf "%-30s %10.2f\n" "simpleFoam (CPU)" "$CPU_TIME"
printf "%-30s %10.2f\n" "simpleHIPFoam (CPU mode)" "$HIP_CPU_TIME"
printf "%-30s %10.2f\n" "simpleHIPFoam (GPU mode)" "$GPU_TIME"
echo ""

SPEEDUP_VS_SIMPLEFOAM=$(echo "scale=2; $CPU_TIME / $GPU_TIME" | bc)
SPEEDUP_VS_CPU_MODE=$(echo "scale=2; $HIP_CPU_TIME / $GPU_TIME" | bc)

echo -e "${GREEN}Speedup Analysis:${NC}"
printf "  GPU vs simpleFoam:        ${GREEN}%.2fx${NC} faster\n" "$SPEEDUP_VS_SIMPLEFOAM"
printf "  GPU vs CPU mode:          ${GREEN}%.2fx${NC} faster\n" "$SPEEDUP_VS_CPU_MODE"
echo ""

# GPU info
if command -v rocm-smi &> /dev/null; then
    echo -e "${BLUE}GPU Information:${NC}"
    rocm-smi --showproductname | grep "GPU\|Card"
    echo ""
fi

# Save results
RESULTS_FILE="benchmark_results_$(date +%Y%m%d_%H%M%S).txt"
cat > $RESULTS_FILE << EOF
Benchmark Results
=================
Date: $(date)
Mesh: $NCELLS cells

Timing Results (seconds):
  simpleFoam (CPU):          $CPU_TIME
  simpleHIPFoam (CPU mode):  $HIP_CPU_TIME
  simpleHIPFoam (GPU mode):  $GPU_TIME

Speedup:
  GPU vs simpleFoam:  ${SPEEDUP_VS_SIMPLEFOAM}x
  GPU vs CPU mode:    ${SPEEDUP_VS_CPU_MODE}x

GPU Info:
$(rocm-smi --showproductname 2>/dev/null || echo "N/A")
EOF

echo -e "${GREEN}Results saved to: $RESULTS_FILE${NC}"
echo ""
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}  Benchmark Complete!${NC}"
echo -e "${CYAN}========================================${NC}"