using AsapSim
@static if VERSION < v"0.7.0-DEV.2005"
    using Base.Test
else
    using Test
end

import DataStructures
using MacroTools
using BenchmarkTools

#include("assembler/macro.jl")
#include("assembler/test_program.jl")
#
#include("fifo.jl")
#include("core/stall.jl")
include("core/alu.jl")
