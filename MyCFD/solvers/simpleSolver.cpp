// solvers/simpleSolver.cpp
#include "../include/field.h"
#include <iostream>

void simpleSolver(ScalarField &field, int nSteps) {
    for (int t = 0; t < nSteps; t++) {
        for (int i = 0; i < field.size(); i++) {
            field.data[i] += 1.0;  // simple operation
        }
    }
    std::cout << "CPU solver finished\n";
}
