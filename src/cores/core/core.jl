# Condition and ALU flags for conditional execution, etc.
#
# Make this a struct with an API to possibly reimplement as a single integer
# with bit-twiddling instead of a struct of Bools. Probably not needed but
# may save some space in the future.
struct ALUFlags
    carry       :: Bool
    negative    :: Bool
    overflow    :: Bool
    zero        :: Bool
end
ALUFlags() = ALUFlags(false, false, false, false)

# ------------------------- #
# --- Address Generator --- #
# ------------------------- #

# Things to think about: 
#
# * Maybe make the "number of bits" for the address generator a parameter if
# we ever want have generators outside of the 8-bit range of Asap4
#
# * Think about write-back timings.

@with_kw_noshow mutable struct AddressGenerator
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
    ag.start = start
    ag.stop  = stop
    ag.current = ag.start
    return nothing
end

function set_stride!(ag::AddressGenerator, stride)
    ag.stride = stride
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
rollback!(ag::AddressGenerator) = ag.current = ag.old


mutable struct CondExec
    flag        :: Bool
    mask        :: Int16
    # One of :OR, :AND, :XOR
    unary_op    :: Symbol
    early_kill  :: Bool
end
CondExec() = CondExec(false, 0, :OR, false)

function set!(c::CondExec, mask)
    # Get bit 13 for the early kill.
    c.early_kill = isbitset(mask, 13)

    # Get bits 12 and 11 for the reduction operator.
    #
    # If OO or 01, use OR
    # If 10, use AND
    # If 11, use XOR
    if isbitset(mask, 12)
        if isbitset(mask, 11)
            c.unary_op = :XOR
        else
            c.unary_op = :AND
        end
    else
        c.unary_op = :OR
    end
    c.mask = mask
    return nothing
end

# For keeping track of instructions through the pipeline.
# Essentially just a wrapper for the instruction with an extra slot for the
# result.
struct PipelineEntry
    instruction :: AsapInstruction# = NOP()
    # The actual source and result values
    src1_value  :: Int16# = 0
    src2_value  :: Int16# = 0
    result      :: Int16# = 0

    # Data for rolling-back branches. This doesn't really need to be recorded
    # at every stage, but it will be cleaner to do it this way. It doesn't take
    # that much memory anyways.
    old_return_address :: Int64# = 0
    old_alternate_pc   :: Int64# = 0
    old_repeat_count   :: Int64# = 0
end

PipelineEntry(instruction = NOP()) = PipelineEntry(instruction,0,0,0,0,0,0)

# Convenience types for changing fields of the PipelineEntry immutable
# struct.
struct SRC <: Mutator{PipelineEntry}
    src1_value :: Int16
    src2_value :: Int16
end
struct RESULT <: Mutator{PipelineEntry}
    result::Int16
end
struct INSTRUCTION <: Mutator{PipelineEntry}
    instruction::AsapInstruction
end
struct RETURNS <: Mutator{PipelineEntry}
    old_return_address :: Int64
    old_alternate_pc   :: Int64
    old_repeat_count   :: Int64
end

# Asap Pipeline.
#
# Note: The data in each stage is the END of each stage.
mutable struct AsapPipeline
    stage1 :: PipelineEntry
    stage2 :: PipelineEntry
    stage3 :: PipelineEntry
    stage4 :: PipelineEntry
    stage5 :: PipelineEntry
    stage6 :: PipelineEntry
    stage7 :: PipelineEntry
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
)

# Basic AsapCore. Parameterize based on
#
# 1. The type of FIFO - allows for injection of TestFifos to help with tests
@with_kw mutable struct AsapCore{F <: AbstractFifo}
    # --- Timing Control --- #

    # Clock period - for registering updates.
    # This number is inherently meaningless, but should usually be interpreted
    # as PS.
    #
    # Note that if interpreting this as PS ... a default value of 1 does not
    # really make a whole lot of sense.
    clock_period ::Int64 = 1

    # --- Program --- #

    # Stored program and program counter.
    program ::Vector{AsapInstruction} = AsapInstruction[]

    # Note on Program Counter (pc) - In actual hardware, it is base 0 ...
    # because hardware is base 0. However, Julia is base 1, so we'll have to
    # keep that in mind.
    pc                  :: Int64 = 0

    # Hardware registers holding information about repeat values.
    repeat_count  :: Int64 = 0
    repeat_start  :: Int64 = 0
    repeat_end    :: Int64 = 0

    # Hardware return address buffer.
    return_address :: Int16 = 0

    # Number of pending NOPs to inser in stage 3 of the pipeline.
    # This is set by the options in the assembler.
    pending_nops :: Int16 = 0

    # Mispredicted branch - done in S4
    branch_mispredict :: Bool = false

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

    # -------- #
    # Pipeline #
    # -------- #
    pipeline::AsapPipeline = AsapPipeline()
end

function setobufmask!(core, mask)
    for index in 1:length(core.obuf_mask)
        core.obuf_mask[index] = isbitset(mask, index - 1)
    end
end

# Convert from index 0 to index 1.
dmem(core, address) = core.dmem[address + 1]


################################################################################
# Stall Detection
################################################################################

"""
    StallSignals
    
Collection of stall signals that can occur in the Asap4 processor.

Parameters:

* `stall_01` - Stall stages 0 and 1. Happens if stalled on a fifo or if stage
    2 has pending NOPS to insert.
* `nop_2` - Insert NOPs into Stage 2. Happens when there are pending NOPs.
* `stall_234` - Stall stages 2, 3, and 4. Happens if stalled on fifo.
* `stall_5678` - Stall stages 5, 6, and 7. Happens if stalled on a fifo and none
    of the destinations in stages 5, 6, and 7 is an output.
* `nop_5` - Insert NOPS into stage 5. Happens if stalled on an output but
    one of the destinations in stages 5, 6, or 7 is an output.
"""
struct StallSignals
    stall_01   :: Bool
    nop_2      :: Bool
    stall_234  :: Bool 
    stall_5678 :: Bool
    nop_5      :: Bool
end

function stall_check(core::AsapCore)
    # Check if stalled on a FIFO.
    fifo_stall = stall_fifo_check(core)

    # Default stall signals to "false"
    stall_01 = false
    nop_2 = false
    stall_234 = false
    stall_5678 = false
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
            stall_5678 = true
        end

    # Otherwise, stall stages 0 and 1 if stage 2 has pending NOPs or will
    # request NOPs this cycle.
    else
        # Like in the RTL for asap4, if pending nops = 1, we're on the last
        # NOP, so we can stop the NOP signal then.
        if core.pending_nops > 0
            stall_01 = true
            nop_2 = true
        elseif core.pipeline.stage2.instruction.nops > 0
            stall_01 = true
        end
    end

    # Return a collection of stall signals.
    return StallSignals(
        stall_01,
        nop_2,
        stall_234,
        stall_5678,
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
    stage3 = core.pipeline.stage3

    # Early termination of stage 3 is a NOP - NOPs can't stall.
    stage3.instruction.op == :NOP && (return false)

    # If this instruction is a STALL instruction, pass its mask is found in
    # the src1_value field
    if stage3.instruction.op == :STALL
        return stall_check_stall_op(core, stage3.src1_value)        

    # Otherwise, do a normal stall check.
    else
        return stall_check_io(core, stage3.instruction)
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
    if default == true && isreadready(core.fifos[index]) 
        return false

    # Otherwise, if the default is not to stall, return "true" if the fifo is
    # empty to indicate the core should stall
    elseif default == false && !isreadready(core.fifos[index]) 
        return true

    # If the above conditions are not met, just return the default.
    else
        return default
    end
end

function stall_check_obuf(core, index, default :: Bool) :: Bool
    # Logic is similar to the ibuf check, but looks for full fifos instead of
    # empty fifos.
    if default == true && iswriteready(core.outputs[index])
        return false
    elseif default == false && !iswriteready(core.outputs[index])
        return true
    else
        return default
    end
end

"""
    checkoutputs(core::AsapCore)

Return `true` if any of the output buffers selected by `core`'s obuf_mask is
full. Otherwise, return `false`.
"""
function checkoutputs(core::AsapCore)
    for (index, bit) in enumerate(core.obuf_mask)
        bit || continue
        if !iswriteready(core.outputs[index])
            return true
        end
    end
    return false
end
