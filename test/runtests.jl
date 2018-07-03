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

# Fifo Tests
# include("fifo.jl")
# include("cores/fifos/fifo.jl")

# IO Handlers
include("cores/io/io.jl")
# 
# Core Component Tests
# include("cores/core/stall.jl")
include("cores/core/alu.jl")
include("cores/core/programs.jl")
include("cores/core/sort.jl")

include("sim/snakesort.jl")
