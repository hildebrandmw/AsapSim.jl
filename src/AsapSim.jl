module AsapSim

# Use this to provide default values to a bunch of fields of structs.
using Parameters
using MacroTools

include("assembler/assembler.jl")

include("cores/fifo.jl")
include("cores/core/core.jl")
include("cores/core/pipeline.jl")


end # module
