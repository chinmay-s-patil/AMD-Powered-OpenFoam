#pragma once
#include <vector>
#include <iostream>

class ScalarField {
public:
    int N;
    float *data;   // GPU-friendly, we’ll allocate on device later

    ScalarField(int N_) : N(N_) {
        data = new float[N];
        for(int i=0; i<N; i++) data[i] = 0.0f;
    }

    ~ScalarField() {
        delete[] data;
    }

    void printFirst10() {
        std::cout << "Field[0..9]: ";
        for(int i=0; i<10 && i<N; i++)
            std::cout << data[i] << " ";
        std::cout << std::endl;
    }
};
