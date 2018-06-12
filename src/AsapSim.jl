module AsapSim

# Use this to provide default values to a bunch of fields of structs.
using Parameters
using MacroTools

include("cores/fifo.jl")
include("assembler/assembler.jl")


end # module
