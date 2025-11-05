// File: AMDPoweredOpenFoam/applications/solvers/simpleHIPFoam/simpleHIPFoam.C
// Main application for HIP-accelerated SIMPLE algorithm solver
// Compatible with OpenFOAM v2412

#include "fvCFD.H"
#include "singlePhaseTransportModel.H"
#include "turbulentTransportModel.H"
#include "simpleControl.H"
#include "fvOptions.H"
#include "hipSolver/hipSIMPLE.H"

int main(int argc, char *argv[])
{
    argList::addNote
    (
        "Steady-state solver for incompressible, turbulent flows "
        "using HIP/ROCm acceleration for linear solvers."
    );

    #include "postProcess.H"
    #include "addCheckCaseOptions.H"
    #include "setRootCaseLists.H"
    #include "createTime.H"
    #include "createMesh.H"
    #include "createControl.H"
    #include "createFields.H"
    #include "initContinuityErrs.H"

    turbulence->validate();

    // Initialize HIP solver
    Info<< "\nInitializing HIP acceleration..." << endl;
    hipSIMPLE hipSolver(mesh, p, U, phi);
    
    Info<< "\nStarting time loop\n" << endl;

    while (simple.loop())
    {
        Info<< "Time = " << runTime.timeName() << nl << endl;

        // --- Pressure-velocity SIMPLE corrector
        {
            #include "UEqn.H"
            #include "pEqn.H"
        }

        laminarTransport.correct();
        turbulence->correct();

        runTime.write();

        runTime.printExecutionTime(Info);
    }

    Info<< "End\n" << endl;

    return 0;
}
