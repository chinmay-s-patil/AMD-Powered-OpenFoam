#!/bin/bash
# Wrapper to run simpleHIPFoam with proper environment

# Set OpenFOAM environment manually
export WM_PROJECT_DIR="/home/indigo/OpenFOAM/OpenFOAM-v2412"
export FOAM_USER_APPBIN="/home/indigo/OpenFOAM/indigo-v2412/platforms/linux64GccDPInt32Opt/bin"
export PATH="/home/indigo/OpenFOAM/OpenFOAM-v2412/platforms/linux64GccDPInt32Opt/bin:$PATH"
export LD_LIBRARY_PATH="/home/indigo/OpenFOAM/OpenFOAM-v2412/platforms/linux64GccDPInt32Opt/lib:$LD_LIBRARY_PATH"

# Set ROCm environment
export ROCM_PATH=/opt/rocm
export PATH=$ROCM_PATH/bin:$PATH
export LD_LIBRARY_PATH=$ROCM_PATH/lib:$LD_LIBRARY_PATH

# Run solver
/home/indigo/OpenFOAM/indigo-v2412/platforms/linux64GccDPInt32Opt/bin/simpleHIPFoam "$@"
