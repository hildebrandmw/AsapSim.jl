# Set of opcodes in the instruction set for the Asap4 Processor.

# Opcode format:
# 3b condex, 2b NOP, 1b Ext, 9b Src2, 9b Src1, 9b Dest, 6b Opcode.

# Instructions with three operands:
#   inst dst src1 src2 [options]

@enum OpType::Int8 NOP_TYPE ALU_TYPE MAC_TYPE BRANCH_TYPE OTHER_TYPE PSUEDO_TYPE

@with_kw_noshow struct InstructionDefinition
    opcode :: Symbol
    # True if this instruction has these fields.
    dest :: Bool = true
    src1 :: Bool = true
    src2 :: Bool = true

    # Classification of operand type
    optype :: OpType
    signed :: Bool = false
    saturate :: Bool = false
end

# Convenience constructor so we don't have to write "opcode" and "optype"
# all the time.
function InstructionDefinition(opcode::Symbol, optype::OpType; kwargs...)
    return InstructionDefinition(;
        opcode = opcode,
        optype = optype,
        kwargs...
    )
end


const InstD = InstructionDefinition

# Define all of the Instructions
const AsapInstructionList = (
    # --- Instructions using all 3 operands --- #

    # Unsigned Arithmetic
    InstD(:ADDU,   ALU_TYPE),
    InstD(:ADDSU,  ALU_TYPE, saturate = true),
    InstD(:ADDCU,  ALU_TYPE),
    InstD(:ADDCSU, ALU_TYPE, saturate = true),
    InstD(:SUBU,   ALU_TYPE),
    InstD(:SUBSU,  ALU_TYPE, saturate = true),
    InstD(:SUBCU,  ALU_TYPE),
    InstD(:SUBCSU, ALU_TYPE, saturate = true),

    # Signed Arithmetic
    InstD(:ADD,    ALU_TYPE, signed = true),
    InstD(:ADDS,   ALU_TYPE, signed = true, saturate = true),
    InstD(:ADDC,   ALU_TYPE, signed = true),
    InstD(:ADDCS,  ALU_TYPE, signed = true, saturate = true),
    InstD(:SUB,    ALU_TYPE, signed = true),
    InstD(:SUBS,   ALU_TYPE, signed = true, saturate = true),
    InstD(:SUBC,   ALU_TYPE, signed = true),
    InstD(:SUBCS,  ALU_TYPE, signed = true, saturate = true),

    # Logic Operatins
    InstD(:OR,  ALU_TYPE),
    InstD(:AND, ALU_TYPE),
    InstD(:XOR, ALU_TYPE),

    # 3 operand conditional moves
    InstD(:MOVC, ALU_TYPE),
    InstD(:MOVZ, ALU_TYPE),
    InstD(:MOVCX0, ALU_TYPE),
    InstD(:MOVCX1, ALU_TYPE),

    # Shifts
    InstD(:SHL,  ALU_TYPE),
    InstD(:SHR,  ALU_TYPE),
    InstD(:SRA,  ALU_TYPE),
    InstD(:SHLC, ALU_TYPE),
    InstD(:SHRC, ALU_TYPE),
    InstD(:SRAC, ALU_TYPE),

    # Multiplication
    InstD(:MULTL,  MAC_TYPE, signed = true),
    InstD(:MULTH,  MAC_TYPE, signed = true),
    InstD(:MULTLU, MAC_TYPE),
    InstD(:MULTHU, MAC_TYPE),

    # MACC
    InstD(:MACL,   MAC_TYPE, signed = true),
    InstD(:MACH,   MAC_TYPE, signed = true),
    InstD(:MACCL,  MAC_TYPE, signed = true),
    InstD(:MACCH,  MAC_TYPE, signed = true),
    InstD(:MACLU,  MAC_TYPE),
    InstD(:MACHU,  MAC_TYPE),
    InstD(:MACCLU, MAC_TYPE),
    InstD(:MACCHU, MAC_TYPE),

    # --- Operatins without a SRC2 ---

    # Unconditional moves
    InstD(:MOVE,    ALU_TYPE, src2 = false),
    InstD(:MOVI,    ALU_TYPE, src2 = false),
    # Unary Reductions
    InstD(:ANDWORD, ALU_TYPE, src2 = false),
    InstD(:ORWORD,  ALU_TYPE, src2 = false),
    InstD(:XORWORD, ALU_TYPE, src2 = false),
    # Misc Logic
    InstD(:BTRV,    ALU_TYPE, src2 = false),
    InstD(:LSD,     ALU_TYPE, src2 = false),
    InstD(:LSDU,    ALU_TYPE, src2 = false),
    # Accumulate
    InstD(:ACCSH,   MAC_TYPE, src2 = false, signed = true),
    InstD(:ACCSHU,  MAC_TYPE, src2 = false),

    # --- Instructions without a SRC2 or DEST
    InstD(:RPT,   OTHER_TYPE, src2 = false, dest = false),
    InstD(:BR,    BRANCH_TYPE, src2 = false, dest = false),
    InstD(:BRL,   BRANCH_TYPE, src2 = false, dest = false),
    InstD(:STALL, OTHER_TYPE, src2 = false, dest = false),

    # --- Instructions with no arguments ---
    InstD(:NOP, NOP_TYPE, src1 = false, src2 = false, dest = false),

    # --- Pseudo instructions --- 
    # Appear in input assembly but not in output program.
    InstD(:END_RPT, PSUEDO_TYPE, src1 = false, src2 = false, dest = false),
)

# Create a dictionary mapping opcodes to their instruction definition
const Instruction_Dict = Dict(i.opcode => i for i in AsapInstructionList)
isop(x::Symbol) = haskey(Instruction_Dict, x)
getdef(x::Symbol) = Instruction_Dict[x]

const output_dests = (
    :output,
)

#=
The general idea here is that a macro will be created that can take
pseudo-assembly much like the C++ version of the simulator and turn it into
a vector of type AsapInstruction. Core models will then have this vector of
instructions as their program and keep a local PC to point to which instruction
they are executing on a given clock cycle.

Lables will be encoded using the standard Julia @label macro. During source code
tansformation, labels will be converted to indices of instructions in the
final vector of instructions.

- Alternatives:

This could be encoded using something like a ResumableFunction from the
ResumableFunctions package, but I feel like it would be difficult to bind the
functions to their respecitve cores in a clear and mostly type-stable manner.

Plus, using the vector of instructions format would allow an assembler to take
assembly files generated by the compiler and execute them without needing
to recompile any code.

=#

# All the symbols for expected sources in the Asap4 architecture.
const SourceSymbols = (
    :dmem,      # data memory (index needed)
    :immediate, # immediate
    :ibuf,      # input fifo (index needed)
    :ibuf_next, # input fifo, no increment (index needed)
    :bypass,    # bypass resigter (index needed)
    :pointer,   # dereference hardware pointer (index needed)
    :ag,        # dereference address generator, no increment (index needed)
    :ag_pi,     # dereference address generator, increment (index needed)
    :pointer_bypass, # dereference bypass register 1.
    :acc,       # read lower 16 bits from accumulator
    :ret,       # read return address

    # --- Unimplemented --- #
    # :external_mem
    # :external_mem_next
    # :packet_router
    # :packet_router_next
)


#-------------------------------------------------------------------------------
# Destination encoding

const DestinationSymbols = (
    :dmem,      # data memory (index needed)
    # TODO: For the dcmem, will probably be helpful to put in aliases for 
    # common operations to help with the readability of assembly.
    :dcmem,     # dynamic configuration memory (index needed)
    :pointer,   # set hardware pointers (index needed)
    :ag,        # dereference address generator, no increment (index needed)
    :ag_pi,     # dereference address generator, increment (index needed)
    :pointer_bypass, # dereference bypass register 1
    :null,       # No write back
    :output,     # Write to OBUF, directions starting at 0 are:
        # east, north, west, south, right, up, left, down. (index needed)
    :obuf,       # Write to all output broadcast directions.

    # --- Unimplemented ---#
    # :external_mem
    # :packet_router
    # :dynamic_net
    # :done_flag
    # :start_pulse_test
)

const DestinationOutputs = (
    :output,
    :obuf,
)


# Intermediate form for an instruction.
# The pseudo-assembly will be parsed directly into these intermediate
# instructions, which will then be analyzed to emit the final vector of
# AsapInstructions.
mutable struct AsapIntermediate
    op   :: Symbol
    args :: Vector{Any}

    # The label assigned to this instruction
    label       :: Union{Symbol,Void}
    # The end-address if this is a repeat instruction
    repeat_start :: Union{Int64, Void}
    repeat_end  :: Union{Int64,Void}

    # Store the file and line numbers to provide better error messages while
    # converting the intermediate instructions into full instructions.
    file :: Symbol
    line :: Int64
end

# Convenience constructors.
function AsapIntermediate(
        op      ::Symbol, 
        args    ::Vector, 
        label = nothing;
        #kwargs
        repeat_start = nothing,
        repeat_end = nothing,
        file = :null,
        line = 0
    ) 

    return AsapIntermediate(op, args, label, repeat_start, repeat_end, file, line)
end

# For equality purposes, ignore file and line. Makes for easier testing.
# If "file" and "line" become important for testing function equality, I may
# have to revisit this.
Base.:(==)(a::T, b::T) where {T <: AsapIntermediate} = 
    a.op == b.op &&
    a.args == b.args &&
    a.label == b.label &&
    a.repeat_start == b.repeat_start &&
    a.repeat_end == b.repeat_end


function oneofin(a, b)
    for i in a
        i in b && return true
    end
    return false
end

# Enums for instruction type and conditional execution
@enum CXFlag::Int8 NO_CX CX_SET CX_TRUE CX_FALSE 

function getoptions(args)
    # Construct an empty container for kwargs for the options.
    kwargs = Pair{Symbol,Any}[]
    # Check for nops. Iterate in the order of number of NOPS for style points.
    nops = zero(Int8)
    for (i, nop) in enumerate((:nop1, :nop2, :nop3))
        if nop in args
            nops = Int8(i)
        end
    end
    # Save nop argument if not zero
    if !iszero(nops)
        push!(kwargs, (:nops => nops))
    end
    # Check fo jump
    if :j in args
        push!(kwargs, (:jump => true))
    end

    # Check for conditional execution
    csx = oneofin((:csx0, :csx1, :cxt0, :cxt1, :cfx0, :cfx1), args)
    if csx
        # Set flag type
        if oneofin((:csx0, :csx1), args)
            push!(kwargs, (:cxflag => CX_SET))
        elseif oneofin((:cxt0, :cxt1), args)
            push!(kwargs, (:cxflag => CX_TRUE))
        else
            push!(kwargs, (:cxflag => CX_FALSE))
        end

        # Figure out the index of the conditional execution flag.
        if oneofin((:csx0, :cxt0, :cxf0), args)
            cx_index = UInt8(0)
        else
            cx_index = UInt8(1)
        end
        push!(kwargs, (:cxindex => cx_index))
    end
    # Check double write
    if :dw in args
        push!(kwargs, (:sw => false))
    end

    return kwargs
end

@with_kw_noshow struct AsapInstruction
    # The opcode of the instruction. Set the defaultes for the "with_kw" 
    # constructor to be a "nop" if constructed with no arguments.
    op :: Symbol = :NOP

    # Sources and destination will come in pairs
    # 1. A Symbol, indication the name of the source or destination. Use symbols
    #    instead of Strings or Integers because Symbols are interred in Julia 
    #    and thus compare for equality faster than strings, and are clearer
    #    visually than integers.
    # 
    # 2. An extra metadata value as an integer. For some sources/destinations,
    #    such as dmem references, this integer will serve as an index, allowing
    #    for fast decoding.
    #
    #    For other instructions, like immediates or branches, this index will
    #    store other information like branch address, immediate value, or
    #    start and end addresses for RPT loops. Convenient setter and accessor
    #    functions will be provided so this doesn't have to be esplicitly 
    #    remembered
    src1       :: Symbol = :null
    src1_index :: Int64  = -1

    src2       :: Symbol = :null
    src2_index :: Int64  = -1

    dest       :: Symbol = :null
    dest_index :: Int64  = -1

    # ------------------------ #
    # Options for instructions #
    # ------------------------ #

    # Number of no-ops to put after this instruction.
    nops :: Int8 = zero(Int8)
    # Set the "jump" flag for branches
    jump :: Bool = false
    # Mark branch instructions as a return instruction.
    isreturn :: Bool = false
    # conditional execution
    # TODO: Make this an enum for smaller storage?
    cxflag :: CXFlag = NO_CX
    # Index of the conditional register to use.
    cxindex::Int8 = zero(Int8)
    # Options for writeback to dmem. If "true", single-write will happen
    # Default to this as it should be the common case and to bring it into
    # alignment with the c++ simulator
    sw::Bool = true

    # Metadata for faster decoding during Stage 4 arithmetic or for performing
    # stall detection
    signed      :: Bool = false
    saturate    :: Bool = false
    # For fast differentiation between ALU and MAC instructions
    optype          :: OpType   = NOP_TYPE
    dest_is_output  :: Bool     = false
end


immutable SrcDestCollection
    src1        :: Symbol
    src1_index  :: Int
    src2        :: Symbol
    src2_index  :: Int
    dest        :: Symbol
    dest_index  :: Int
end

# Here's a method to change the src's and dest of an instruction quickly 
# (using only the positional constructor rather than one generated by @with_kw)
#
# This is helpful for Stage 2 where pointers are dereferenced and turned into
# memory locations.
#
# Make this a @generated function so it keeps working even if the other fields
# of the AsapInstruction change.
@generated function reconstruct(inst::AsapInstruction, operands::SrcDestCollection)
    # Get the fieldnames for the two arguments.
    inst_fields = fieldnames(inst)
    operands_fields = fieldnames(operands)

    # Build up a list of arguments for a positional constructor of AsapInstruction
    # by iterating ove inst_fields. If a given field is in the SrcDestCollection,
    # use that instead.
    args = map(inst_fields) do f
        i = findfirst(operands_fields, f)
        # If "i" is in the operands fields, return that field.
        return i > 0 ? :(operands.$f) : :(inst.$f)
    end

    return :(AsapInstruction($(args...)))
end

# Alias "NOP" to an empty constructor, which should provide a NOP by default.
const NOP = AsapInstruction


# Methods on instructions - Since some values may be stored in some 
# less-than-obvious places, use these methods to get these fields if needed.

# Get branch-target - This is encoded in the "dest_val" field of the branch
# instructions.
function branch_target(i::AsapInstruction) 
    # For debugging, ensure that this is only called on branch instructions.
    # If not, something ahs gone wrong.
    @assert i.op == :BR || i.op == :BRL
    return i.dest_index
end

# For repeat start, use src2_index. src1_index may be used if the RPT instruction
# uses a dmem or other source
repeat_start(i::AsapInstruction) = i.src2_index

# Similarlym, use the dest_index for the repeat end.
repeat_end(i::AsapInstruction) = i.dest_index

set_branch_target(x) = (:dest_index => x)
set_repeat_start(x) = (:src2_index => x)
set_repeat_end(x) = (:dest_index => x)
