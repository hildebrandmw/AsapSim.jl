module AsapSim

# Use this to provide default values to a bunch of fields of structs.
using Parameters
using MacroTools
import AutoAligns

export  @asap4asm,
        AsapCore,
        AsapInstruction,
        AsapInstructionKeyword,
        InstructionLabelPair,
        Loc,
        assemble,
        # Accessors for Core types.
        dmem

include("assembler/assembler.jl")

include("cores/fifo.jl")
include("cores/core/core.jl")
include("cores/core/pipeline.jl")
include("cores/core/show.jl")


end # module
