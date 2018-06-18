# Condition and ALU flags for conditional execution, etc.
#
# Make this a struct with an API to possibly reimplement as a single integer
# with bit-twiddling instead of a struct of Bools. Probably not needed but
# may save some space in the future.
mutable struct ALUFlags
    carry       :: Bool
    negative    :: Bool
    overflow    :: Bool
    zero        :: Bool
end
ALUFlags() = ALUFlags(false, false, false, false)

mutable struct AddressGenerator
    start       ::Int16
    stop        ::Int16
    current     ::Int16
    stride      ::Int16
end
AddressGenerator() = AddressGenerator(0,0,0,0)

mutable struct CondExec
    flag        :: Bool
    mask        :: Int16,
    unary_op    :: Int16
    early_kill  :: Bool
end
CondExec() = CondExec(false, 0, 0, false)

# For keeping track of instructions through the pipeline.
# Essentially just a wrapper for the instruction with an extra slot for the
# result.
@with_kw mutable struct PipelineEntry
    instruction :: AsapInstruction
    # The actual source and result values
    src1_value  :: Int16 = 0
    src2_value  :: Int16 = 0
    result      :: Int16 = 0

    # Data for rolling-back branches. This doesn't really need to be recorded
    # at every stage, but it will be cleaner to do it this way. It doesn't take
    # that much memory anyways.
    old_return_address :: Int64 = 0 
    old_pc_plus_1      :: Int64 = 0
    old_repeat_count   :: Int64 = 0
end

PipelineEntry(i::AsapInstruction = NOP()) = PipelineEntry(instruction = i)
function PipelineEntry(core::AsapCore, inst::AsapInstruction = NOP())
    return PipelineEntry(
        instruction = inst,
        old_return_address  = core.return_address
        old_pc_plus_1       = core.pc + 1
        old_repeat_count    = core.repeat_count
    )
end

# Only record the states in stages 3-8. Stages 1-2 are decode stages so there's
# not much interesting to record there.
mutable struct AsapPipeline
    stage1 :: PipelineEntry
    stage2 :: PipelineEntry
    stage3 :: PipelineEntry
    stage4 :: PipelineEntry
    stage5 :: PipelineEntry
    stage6 :: PipelineEntry
    stage7 :: PipelineEntry
    stage8 :: PipelineEntry
end

# Initialize to an empty pipeline.
AsapPipeline() = AsapPipeline(
    PipelineEntry(),
    PipelineEntry(),
    PipelineEntry(),
    PipelineEntry(),
    PipelineEntry(),
    PipelineEntry(),
    PipelineEntry(),
    PipelineEntry(),
)


@with_kw mutable struct AsapCore
    # --- Timing Control --- #

    # Clock period - for registering updates.
    clock_period :: Int64

    # --- Program --- #

    # Stored program and program counter.
    program ::Vector{AsapInstruction} = AsapInstruction[]
    repeat_count        :: Int64 = 0
    repeat_block_start  :: Int64 = 0
    repeat_block_end    :: Int64 = 0
    pc                  :: Int64 = 1

    # Note on Program Counter (pc) - In actual hardware, it is base 0 ... 
    # because hardware is base 0. However, Julia is base 1, so we'll have to
    # keep that in mind.

    # Mispredicted branch - done in S4
    branch_mispredict :: Bool = false

    # Stall signals. 
    # Note that stages 0 and 1 stall together
    # Stages 3 and 4 stall together
    # Stages 5, 6, 7, 8 stall together
    # TODO: Where does stage 2 stall.
    stall_01 :: Bool = false
    stall_2  :: Bool = false
    stall_34 :: Bool = false
    stall_5678 :: Bool = false


    # --- Misc storage elements --- #

    # Input fifo - default the element types of the fifo to Int16s.
    fifos::Vector{DualClockFifo{Int16}} = [
        DualClockFifo(Int16, 32),
        DualClockFifo(Int16, 32),
    ]

    # Set this up as a Dict to handle cases where directions do not have
    # connected outputs.
    #
    # NOTE: In Julia 0.7+, small unions are faster, so it may be possible to
    # convert this to a Union{Void,DualClockFifo{Int16}} without incurring
    # any nasty runtime penalties.
    obufs::Dict{Int,DualClockFifo{Int16}} = Dict{Int,DualClockFifo{Int16}}()

    # Flags
    alu_flags :: ALUFlags = ALUFlags()

    # ---------------------------- #
    # Dynamic Configuration Memory #
    # ---------------------------- #

    # Address generators.
    address_generators::Vector{AddressGenerator} = [
        AddressGenerator(),
        AddressGenerator(),
        AddressGenerator(),
    ]

    # Hardware pointers
    pointers :: Vector{Int16} = zeros(Int16, 4)

    # Conditional execution blocks
    cond_exec :: Vector{CondExec} = [
        CondExec(),
        CondExec(),
    ]

    # Mask for output
    obuf_mask :: BitVector = falses(8)

    # Data memory - again, default element types to Int16
    dmem::Vector{Int16} = zeros(Int16, 256)

    # Hardware return address buffer.
    return_address :: Int16 = 0

    # Number of pending NOPs to inser in stage 3 of the pipeline.
    # This is set by the options in the assembler.
    pending_nops :: Int16 = 0

    # --- Pipeline Bypass Registers --- #
    # NOTE: Get these straight from the instructions in the pipeline.
    # result_s5 :: Int16 = zero(Int16)
    # result_s6 :: Int16 = zero(Int16)
    # result_s8 :: Int16 = zero(Int16)

    # --- Pipeline --- #
    pipeline::AsapPipeline = AsapPipeline()
end

function stall_check(core::AsapCore)
    # TODO: Check if stage 4 is a STALL OP

    # Check destinations and sources for network accesses.
    # Stall will occur if any selected input is empty or any selected output
    # is full.

    # Use bitvectors to scalably store the masks for input and output
    # directions.
    # TODO: Make the number of inputs and output parametric.
    check_ibuf = falses(2)
    check_obuf = falses(8)

    # Get the pipeline stage 4 instruction.
    instruction = core.pipeline.stage4.instruction

    # Check if stag4 instruction is doing an read.
    if instruction.src1 == :fifo || instruction.src1 == :fifo_next
        check_ibuf[instruction.src1_index] = true
    end
    if instruction.src2 == :fifo || instruction.src2 == :fifo_next
        check_ibuf[instruction.src2_index] = true
    end

    # Check if doing a write to an output.
    if instruction.dest == :obuf_mask
        check_obuf = core.obuf_mask
    elseif instruction.dest == :obuf
        check_obuf[instruction.dest_index] = true
    end

    # Flags have been set - check stalls
    for (index, val) in enumerate(check_ibuf)
        # Don't execute if this flag is not set.
        val || continue

        # Check if the corresponding fifo is empry
        isempty(core.fifo[index]) && return true
    end

    # Check for full outputs
    for (index, val) in enumerate(check_obuf)
        # Don't execute if flag is not set
        val || continue
        isfull(core.fifo[index]) && return true
    end

end
