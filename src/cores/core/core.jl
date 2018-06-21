# Condition and ALU flags for conditional execution, etc.
#
# Make this a struct with an API to possibly reimplement as a single integer
# with bit-twiddling instead of a struct of Bools. Probably not needed but
# may save some space in the future.
@with_kw mutable struct ALUFlags
    carry       :: Bool = false
    negative    :: Bool = false
    overflow    :: Bool = false
    zero        :: Bool = false
end

# ------------------------- #
# --- Address Generator --- #
# ------------------------- #

# Things to think about: 
#
# * Maybe make the "number of bits" for the address generator a parameter if
# we ever want have generators outside of the 8-bit range of Asap4
#
# * Think about write-back timings.

@with_kw mutable struct AddressGenerator
    start       ::UInt8 = 0
    stop        ::UInt8 = 0
    current     ::UInt8 = 0
    # Old value of the pointer. For rolling back in case of branch mispredict.
    old         ::UInt8 = 0
    stride      ::UInt8 = 0
    # Flag to indicate this needs an increment. Used because multiple operands
    # in an instruction can read from the same address generator.
    needs_increment :: Bool = false
end

function set!(ag::AddressGenerator, start, stop)
    ag.start = Int16(start)
    ag.stop  = Int16(stop)
    ag.current = ag.start
    return nothing
end

function set_stride!(ag::AddressGenerator, stride)
    ag.stride = Int16(stride)
    return nothing
end

Base.read(ag::AddressGenerator) = ag.current
mark(ag::AddressGenerator) = ag.needs_increment = true

function increment!(ag::AddressGenerator) 
    # If the address generator does not need to be incremented, do nothing and
    # just return.
    ag.needs_increment || return nothing

    # Save the old pointer value.
    ag.old = ag.current

    # Take advantage of the binary arithmetic of julia - pointer will 
    # automatically wrap around at 256.
    ag.current = (ag.current == ag.stop) ? ag.start : ag.current + ag.stride
    return nothing
end


mutable struct CondExec
    flag        :: Bool
    mask        :: Int16
    # One of :OR, :AND, :XOR
    unary_op    :: Symbol
    early_kill  :: Bool
end
CondExec() = CondExec(false, 0, :OR, false)

# For keeping track of instructions through the pipeline.
# Essentially just a wrapper for the instruction with an extra slot for the
# result.
@with_kw mutable struct PipelineEntry
    instruction :: AsapInstruction = NOP()
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

PipelineEntry(i::AsapInstruction) = PipelineEntry(instruction = i)
function PipelineEntry(core, inst::AsapInstruction)
    return PipelineEntry(
        instruction = inst,
        old_return_address  = core.return_address,
        old_pc_plus_1       = core.pc + 1,
        old_repeat_count    = core.repeat_count,
    )
end

# Asap Pipeline.
#
# Note: The data in each stage is the START of each stage.
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

# Basic AsapCore. Parameterize based on
#
# 1. The type of FIFO - allows for injection of TestFifos to help with tests
@with_kw mutable struct AsapCore{F <: AbstractFifo}
    # --- Timing Control --- #

    # Clock period - for registering updates.
    clock_period :: Int64

    # --- Program --- #

    # Stored program and program counter.
    program ::Vector{AsapInstruction} = AsapInstruction[]

    # Note on Program Counter (pc) - In actual hardware, it is base 0 ...
    # because hardware is base 0. However, Julia is base 1, so we'll have to
    # keep that in mind.
    pc                  :: Int64 = 1

    # Hardware registers holding information about repeat values.
    repeat_count        :: Int64 = 0
    repeat_block_start  :: Int64 = 0
    repeat_block_end    :: Int64 = 0

    # Hardware return address buffer.
    return_address :: Int16 = 0

    # Number of pending NOPs to inser in stage 3 of the pipeline.
    # This is set by the options in the assembler.
    pending_nops :: Int16 = 0

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

    # ---------------------- #
    # Input and Output Fifos #
    # ---------------------- #

    # Input fifo - default the element types of the fifo to Int16s.
    fifos::Vector{F} = [
        DualClockFifo(Int16, 32),
        DualClockFifo(Int16, 32),
    ]

    # Set this up as a Dict to handle cases where directions do not have
    # connected outputs.
    #
    # NOTE: In Julia 0.7+, small unions are faster than in 0.6+, so it may be
    # possible to convert this to a Union{Void,DualClockFifo{Int16}} without
    # incurring any nasty runtime penalties.
    outputs::Dict{Int,F} = Dict{Int,DualClockFifo{Int16}}()

    # Flags
    aluflags :: ALUFlags = ALUFlags()

    # 40-bit accumulator
    # TODO: Think about wrapping this in a type that auto-truncates to
    # a set number of bits.
    accumulator :: Int64 = 0

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
    condexec :: Vector{CondExec} = [
        CondExec(),
        CondExec(),
    ]

    # Mask for output
    obuf_mask :: BitVector = falses(8)

    # ----------- #
    # Data memory #
    # ----------- #

    dmem::Vector{Int16} = zeros(Int16, 256)

    # --- Pipeline Bypass Registers --- #

    # NOTE: Get these straight from the instructions in the pipeline.
    # result_s5 :: Int16 = zero(Int16)
    # result_s6 :: Int16 = zero(Int16)
    # result_s8 :: Int16 = zero(Int16)

    # -------- #
    # Pipeline #
    # -------- #
    pipeline::AsapPipeline = AsapPipeline()
end


################################################################################
# Stall Detection
################################################################################

"""
    StallSignals
    
Collection of stall signals that can occur in the Asap4 processor.

Parameters:

* `stall_01` - Stall stages 0 and 1. Happens if stalled on a fifo or if stage
    2 has pending NOPS to insert.
* `stall_234` - Stall stages 2, 3, and 4. Happens if stalled on fifo.
* `stall_567` - Stall stages 5, 6, and 7. Happens if stalled on a fifo and none
    of the destinations in stages 5, 6, and 7 is an output.
* `nop_5` - Insert NOPS into stage 5. Happens if stalled on an output but
    one of the destinations in stages 5, 6, or 7 is an output.
"""
struct StallSignals
    stall_01  :: Bool
    stall_234 :: Bool 
    stall_567 :: Bool
    nop_5     :: Bool
end

function stall_check(core::AsapCore)
    # Check if stalled on a FIFO.
    fifo_stall = stall_fifo_check(core)

    # Default stall signals to "false"
    stall_01 = false
    stall_234 = false
    stall_567 = false
    nop_5 = false

    # If we're stalled on a fifo, stall stages 0, 1, 2, 3, and 4.
    #
    # Check stages 5, 6, and 7 to see if they are writing to an output.
    # If not, stall stages 5, 6, and 7 also.
    if fifo_stall
        stall_01  = true
        stall_234 = true

        if core.pipeline.stage5.instruction.dest_is_output || 
            core.pipeline.stage6.instruction.dest_is_output ||
            core.pipeline.stage7.instruction.dest_is_output

            nop_5 = true
        else
            stall_567 = true
        end

    # Otherwise, stall stages 0 and 1 if stage 2 has pending NOPs
    else
        if core.pending_nops > 0
            stall_01 = true
        end
    end

    # Return a collection of stall signals.
    return StallSignals(
        stall_01,
        stall_234,
        stall_567,
        nop_5,
    )
end


"""
    stall_fifo_check(core::AsapCore)

Return `true` if the core should stall, `false` otherwise. A core will stall if:

* The instruction in stage 4 is a STALL instruction. In this case, the core will
    only stall if all masked inputs are empty and all masked outputs are full.

* The instruction in stage 4 is NOT a STALL instruction. Then accesses to inputs
    and outputs will be checked. A stall will be generated if any read input is
    empty or any written-to output is full.
"""
function stall_fifo_check(core::AsapCore)
    # Get the pipeline stage 4 instruction.
    stage4 = core.pipeline.stage4

    # Early termination of stage 4 is a NOP - NOPs can't stall.
    stage4.instruction.op == :NOP && (return false)

    # If this instruction is a STALL instruction, pass its mask is found in
    # the src1_value field
    if stage4.instruction.op == :STALL
        return stall_check_stall_op(core, stage4.src1_value)        

    # Otherwise, do a normal stall check.
    else
        return stall_check_io(core, stage4.instruction)
    end
end

"""
    stall_check_stall_op(core::AsapCore, mask::Integer)

Return `true` if `core` should stall as a result of a STALL instruction.
Argument `mask` is the stall bit mask indicating which hardware resources
should be checked.

Core will stall only if all hardware resources checked are stalling. That is,
all inputs are empty and all outputs are full.

The bit encoding is:

* Bit 0: Stall on empty input fifo 0
* Bit 1: Stall on empty input fifo 1
* Bit 2: Stall on empty packet in (TODO)
* Bit 3: Stall on empty memory in (TODO)
* Bit 4: Stall on all obuf_mask direction full
* Bit 5: Stall on full packet out (TODO)
* Bit 6: Stall on full memory out (TODO)
"""
function stall_check_stall_op(core::AsapCore, mask)
    # Set default stall to be true. If any further evaluations break the default
    # We can terminate early.
    default = true

    # Start checking all of the bits. This is a little painful, but I can't
    # really think of a more elegant way to do this.

    # --- Check inputs ---
    if mask & (1 << 0) != 0
        # Note: Converting from index 0 to index 1
        stall_check_ibuf(core, 1, default) != default && return false
    end

    if mask & (1 << 1) != 0
        # Note: Converting from index 0 tio index 1
        stall_check_ibuf(core, 2, default) != default && return false
    end

    # --- Check obuf mask ---
    if mask & (1 << 4) != 0
        # Iterate through the OBUF mask. If a flag is set, check that output.
        for (index, flag) in enumerate(core.obuf_mask)
            flag || continue
            stall_check_obuf(core, index, default) != default && return false
        end
    end

    # Give "unimplemented error" for unimplemented flags. 
    if mask & (0b1101100) != 0
        error("""
        Bits 2, 3, 5, and 6 of the STALL instruction mask are not yet 
        implemented.
        """)
    end

    return default
end

function stall_check_io(core::AsapCore, instruction::AsapInstruction)
    # Default to not stall. Exit early if any IO interaction should cause a
    # stall to happen.
    default = false

    # --- Check inputs ---

    # NOTE: Must do conversion from index 0 to index 1
    if instruction.src1 == :ibuf || instruction.src1 == :ibuf_next
        # The fifo to check should be in the src1_index field of the instruction.
        stall_check_ibuf(core, instruction.src1_index + 1, default) != default && return true
    end

    if instruction.src2 == :ibuf || instruction.src2 == :ibuf_next
        stall_check_ibuf(core, instruction.src2_index + 1, default) != default && return true
    end

    # Check writes to an output
    if instruction.dest == :output
        stall_check_obuf(core, instruction.dest_index + 1, default) != default && return true
    # Check if doing a broadcast. Then, stall if any of the outputs selected
    # by the obuf_mask are stalling.
    elseif instruction.dest == :obuf
        for (index, flag) in enumerate(core.obuf_mask)
            flag || continue
            stall_check_obuf(core, index, default) != default && return true
        end
    end

    # All checks passed, don't stall!
    return default
end

# Break out the various stall checks into a bunch of little functions.

function stall_check_ibuf(core, index, default::Bool) :: Bool
    # If the default value is to stall, return false if the given fifo is
    # not empty to go against the stall.
    if default == true && !isempty(core.fifos[index]) 
        return false

    # Otherwise, if the default is not to stall, return "true" if the fifo is
    # empty to indicate the core should stall
    elseif default == false && isempty(core.fifos[index]) 
        return true

    # If the above conditions are not met, just return the default.
    else
        return default
    end
end

function stall_check_obuf(core, index, default :: Bool) :: Bool
    # Logic is similar to the ibuf check, but looks for full fifos instead of
    # empty fifos.
    if default == true && !isfull(core.outputs[index])
        return false
    elseif default == false && isfull(core.outputs[index])
        return true
    else
        return default
    end
end
