module AsapSim

# Use this to provide default values to a bunch of fields of structs.
using Parameters
using MacroTools
using LightDES
import AutoAligns

export  @asap4asm,
        # AsapOpcode,
        # SrcDest,
        AsapCore,
        AsapInstruction,
        AsapInstructionKeyword,
        InstructionLabelTarget,
        Loc,
        assemble,
        # Accessors for Core types.
        dmem,
        update!,
        summarize,
        showprogram,
        # Fifo Ops
        iswriteready,
        writeupdate!,
        isreadready,
        readupdate!

include("assembler/assembler.jl")

include("cores/fifos/fifo.jl")
include("cores/fifos/dualclockfifo.jl")
include("cores/fifos/testfifo.jl")

include("cores/core/core.jl")
include("cores/core/pipeline.jl")
include("cores/core/show.jl")

include("cores/io/io.jl")

include("sim/sim.jl")


end # module
