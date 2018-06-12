using AsapSim
@static if VERSION < v"0.7.0-DEV.2005"
    using Base.Test
else
    using Test
end

import DataStructures

# write your own tests here
include("fifo.jl")
include("assembler/macro.jl")
