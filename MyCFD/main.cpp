#include "include/field.h"
#include "solvers/hipSolver.h"
#include <iostream>

int main() {
    int N = 1024 * 1024;
    int nSteps = 100;

    ScalarField p(N);
    std::cout << "Starting HIP solver..." << std::endl;
    hipSolver(p, nSteps);

    p.printFirst10();
}
