// File: AMDPoweredOpenFoam/applications/solvers/simpleHIPFoam/pEqn.H
// Pressure equation with HIP acceleration option

volScalarField rAU(1.0/UEqn.A());
volVectorField HbyA(constrainHbyA(rAU*UEqn.H(), U, p));
surfaceScalarField phiHbyA("phiHbyA", fvc::flux(HbyA));

MRF.makeRelative(phiHbyA);

adjustPhi(phiHbyA, U, p);

tmp<volScalarField> trAU;
if (simple.consistent())
{
    trAU = 1.0/(1.0/rAU - UEqn.H1());
    phiHbyA += fvc::interpolate(trAU() - rAU)*fvc::snGrad(p)*mesh.magSf();
    HbyA -= (rAU - trAU())*fvc::grad(p);
}

// Non-orthogonal pressure corrector loop
while (simple.correctNonOrthogonal())
{
    fvScalarMatrix pEqn
    (
        fvm::laplacian(trAU.valid() ? trAU() : rAU, p) == fvc::div(phiHbyA)
    );

    pEqn.setReference(pRefCell, pRefValue);

    // Option 1: Use HIP solver (experimental)
    if (simple.dict().lookupOrDefault<bool>("useHIPSolver", false))
    {
        Info<< "Using HIP-accelerated solver for pressure" << endl;
        
        // In v2412, access the underlying lduMatrix differently
        // Get the lduMatrix from the fvMatrix
        const lduMatrix& mat = pEqn;
        
        // Create a temporary volScalarField for the source
        volScalarField source
        (
            IOobject
            (
                "pEqn_source",
                mesh.time().timeName(),
                mesh,
                IOobject::NO_READ,
                IOobject::NO_WRITE
            ),
            mesh,
            dimensionedScalar("zero", dimless, 0.0)
        );
        
        // Copy source values
        source.primitiveFieldRef() = pEqn.source();
        
        // Convert matrix to CSR and solve on GPU
        hipSolver.convertToCSR(mat);
        hipSolver.solveHIP(p, source, simple.dict().subDict("hipSolver"));
    }
    else
    {
        // Option 2: Use standard OpenFOAM solver
        pEqn.solve();
    }

    if (simple.finalNonOrthogonalIter())
    {
        phi = phiHbyA - pEqn.flux();
    }
}

#include "continuityErrs.H"

// Explicitly relax pressure for momentum corrector
p.relax();

// Momentum corrector
U = HbyA - (trAU.valid() ? trAU() : rAU)*fvc::grad(p);
U.correctBoundaryConditions();
fvOptions.correct(U);
K = 0.5*magSqr(U);
