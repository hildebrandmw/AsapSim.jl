using AsapSim

# Stdlib imports
using Test
using Random
using Profile

# External imports
import DataStructures
using MacroTools
using BenchmarkTools
using LightDES

# Include the TestPrograms package, which contains a collection of programs
# testing portions of the simulator.
include("TestPrograms/src/TestPrograms.jl")
using .TestPrograms

# Assembler tests
include("assembler/macro.jl")

# Fifo Tests
# include("cores/fifos/fifo.jl")

# IO Handlers
include("cores/io/io.jl")

# Core Component Tests
# include("cores/core/stall.jl")
include("cores/core/alu.jl")
include("cores/core/programs.jl")
include("cores/core/sort.jl")

include("sim/snakesort.jl")
