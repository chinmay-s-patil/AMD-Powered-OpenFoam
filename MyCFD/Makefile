# Compiler
HIPCC = hipcc
CXXFLAGS = -O3 -std=c++17

# Build
all: MyCFD

MyCFD: main.cpp solvers/hipSolver.cpp
	$(HIPCC) $(CXXFLAGS) main.cpp solvers/hipSolver.cpp -o MyCFD

clean:
	rm -f MyCFD
