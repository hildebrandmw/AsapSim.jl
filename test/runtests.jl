using AsapSim
@static if VERSION < v"0.7.0-DEV.2005"
    using Base.Test
else
    using Test
end

import DataStructures
using MacroTools
using BenchmarkTools

# Include the TestPrograms package, which contains a collection of programs
# testing portions of the simulator.
include("TestPrograms/TestPrograms.jl")
using .TestPrograms

# Assembler tests
include("assembler/macro.jl")
include("assembler/test_program.jl")

# Fifo Tests
#include("fifo.jl")

# Core Component Tests
include("core/stall.jl")
include("core/alu.jl")
include("core/programs.jl")
include("core/sort.jl")
