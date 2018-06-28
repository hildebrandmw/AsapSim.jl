#=
This is where OpCode definitions and some methods for OpCodes reside.

Originally, opcodes and source/destination identifiers were to be Symbols, 
since Symbols in Julia are interned and thus offer themselves to quick 
comparison. However, I realized that "Symbols" are not actually "bits" types,
rather they are pointers to the actual symbol data that lives on the heap.

Thus, immutable structs containing Symbols contain a reference and thus seem
to be heap allocated. This is true even for small structs. I want to avoid this
because if a bunch of simulated cores are allocating a lot of memory every 
cycle, this will lead to longer GC times.

DISCLAIMER: I did not benchmark an entire system with the Symbol based 
implementation because that was not functional at the time. Rather, I switched
over to the current implementation before the whole system was functional.

--------------------------------------------------------------------------------

The current implementation still uses some of that symbol based ideas, but uses
Enums to encode opcodes and source/destination identifiers.

These enum types are automatically generated from come base constants, so adding
op codes should be easy and automatically propogate to the created Enums.

One downside is that referencing Enums now required prefixing everything with
AsapSim if used outside of this module.

That's generally not a problem because the macro based assembler can take care
of those non-scoped references.
=#


################################################################################
# Instruction Definitions
################################################################################

# This is a collection of the instructions for Asap4.

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

# Gather up all OpCodes and create an Enum out of them.
#
# This macro will gather all the opcodes defined above and create an Enum with
# names corresponding to each opcode.
#
# After the invocation of this macro, key words like ADD, STALL, BR will be this
# enum type.
#
# NOTE: Could just place this inside of an eval() block - though I don't know if
# that would be any cleaner.
macro MakeOpcodeEnums()
    enums = [:($(i.opcode)) for i in AsapInstructionList]
    return esc(:(@enum AsapOpcode $(enums...)))
end
@MakeOpcodeEnums

# Create a dictionary mapping opcodes to their instruction definition
const Instruction_Dict = Dict(i.opcode => i for i in AsapInstructionList)

# Create ways for both the Symbol version and Enum version to access the 
# Instruction_Dict
isop(x::Symbol) = haskey(Instruction_Dict, x)
isop(x::AsapOpcode) = haskey(Instruction_Dict, Symbol(x))
isop(x) = false

getdef(x::Symbol) = Instruction_Dict[x]
getdef(x::AsapOpcode) = Instruction_Dict[Symbol(x)]


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
    :DMEM,      # data memory (index needed)
    :IMMEDIATE, # immediate
    :IBUF,      # input fifo (index needed)
    :IBUF_NEXT, # input fifo, no increment (index needed)
    :BYPASS,    # bypass resigter (index needed)
    :POINTER,   # dereference hardware pointer (index needed)
    :AG,        # dereference address generator, no increment (index needed)
    :AG_PI,     # dereference address generator, increment (index needed)
    :POINTER_BYPASS, # dereference bypass register 1.
    :ACC,       # read lower 16 bits from accumulator
    :RET,       # read return address

    # --- Unimplemented --- #
    # :external_mem
    # :external_mem_next
    # :packet_router
    # :packet_router_next
)

#-------------------------------------------------------------------------------
# Destination encoding

const DestinationSymbols = (
    :DMEM,      # data memory (index needed)
    # TODO: For the dcmem, will probably be helpful to put in aliases for 
    # common operations to help with the readability of assembly.
    :DCMEM,     # dynamic configuration memory (index needed)
    :POINTER,   # set hardware pointers (index needed)
    :AG,        # dereference address generator, no increment (index needed)
    :AG_PI,     # dereference address generator, increment (index needed)
    :POINTER_BYPASS, # dereference bypass register 1
    :NULL,       # No write back
    :OUTPUT,     # Write to OBUF, directions starting at 0 are:
        # east, north, west, south, right, up, left, down. (index needed)
    :OBUF,       # Write to all output broadcast directions.
    :OBUF_MASK,
    :SET_POINTER,
    :AG_START,
    :AG_STRIDE,
    :CXMASK,

    # Return from a branch.
    :BACK,

    # --- Unimplemented ---#
    # :external_mem
    # :packet_router
    # :dynamic_net
    # :done_flag
    # :start_pulse_test
)

const SourceDestSymbols = union(SourceSymbols, DestinationSymbols)


# Do the same trick as we did with Opcodes to create an ENUM for source and
# Destinations.
macro MakeSrcDestEnum()
    vals = [:($i) for i in SourceDestSymbols]
    return esc(:(@enum SrcDest $(vals...)))
end
@MakeSrcDestEnum


# Use this "Loc" type to store instruction source/dest information. It will
# contain a Symbol to identify the name of the source/dest, and an "index" field
# that will be either a true index for accesses to places like dmem or output,
# Or store other information such as immediate values.
struct Loc
    sym::SrcDest
    ind::Int
end

Loc() = Loc(NULL, -1)
Loc(x::Int) = Loc(IMMEDIATE, x)
Loc(x::SrcDest) = Loc(x, -1)
Loc(x::Symbol) = SourceAliases[x]
Loc(x::Loc) = x

Base.:(==)(a::Loc, b::Loc) = (a.sym == b.sym) && (a.ind == b.ind)

Base.convert(::Type{Loc}, x::Union{Int,Symbol,SrcDest}) = Loc(x)

sym(x::Loc) = x.sym
ind(x::Loc) = x.ind

Base.show(io::IO, x::Loc) = print(io, "$(sym(x))[$(ind(x))]")


const SourceAliases = Dict(
    # Inputs
    :ibuf0 => Loc(IBUF, 0),
    :ibuf1 => Loc(IBUF, 1),
    :ibuf0_next => Loc(IBUF_NEXT, 0),
    :ibuf1_next => Loc(IBUF_NEXT, 1),
    # Address Generators
    :ag0pi => Loc(AG_PI, 0),
    :ag1pi => Loc(AG_PI, 1),
    :ag2pi => Loc(AG_PI, 2),
    :ag0   => Loc(AG, 0),
    :ag1   => Loc(AG, 1),
    :ag2   => Loc(AG, 2),
)

const DestinationOutputs = (
    OUTPUT,
    OBUF,
)



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
    csx = oneofin((:cxs0, :cxs1, :cxt0, :cxt1, :cxf0, :cxf1), args)
    if csx
        # Set flag type
        if oneofin((:cxs0, :cxs1), args)
            push!(kwargs, (:cxflag => CX_SET))
        elseif oneofin((:cxt0, :cxt1), args)
            push!(kwargs, (:cxflag => CX_TRUE))
        else
            push!(kwargs, (:cxflag => CX_FALSE))
        end

        # Figure out the index of the conditional execution flag.
        if oneofin((:cxs0, :cxt0, :cxf0), args)
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


# NOTE: There seems to be a problem with @with_kw where the type of the returned
# object cannot be inferred called with no arguments.
struct AsapInstruction
    # The opcode of the instruction. Set the defaultes for the "with_kw" 
    # constructor to be a "nop" if constructed with no arguments.
    op :: AsapOpcode

    # Source and destination values.
    dest :: Loc
    src1 :: Loc
    src2 :: Loc

    # ------------------------ #
    # Options for instructions #
    # ------------------------ #

    # Number of no-ops to put after this instruction.
    nops :: Int8
    # Set the "jump" flag for branches
    jump :: Bool
    # Mark branch instructions as a return instruction.
    isreturn :: Bool
    # conditional execution
    cxflag :: CXFlag
    # Index of the conditional register to use.
    cxindex :: Int8
    # Options for writeback to dmem. If "true", single-write will happen
    # Default to this as it should be the common case and to bring it into
    # alignment with the c++ simulator
    sw :: Bool

    # Metadata for faster decoding during Stage 4 arithmetic or for performing
    # stall detection
    signed      :: Bool
    saturate    :: Bool
    # For fast differentiation between ALU and MAC instructions
    optype          :: OpType
    dest_is_output  :: Bool
end

AsapInstruction() = AsapInstruction(
    NOP,        # op
    Loc(),      # dest
    Loc(),      # src1
    Loc(),      # src2
    zero(Int8), # nops
    false,      # jump
    false,      # isreturn
    NO_CX,      # cxflag
    zero(Int8), # cxindex
    true,       # sw
    false,      # signed
    false,      # saturate
    NOP_TYPE,   # optype
    false,      # dest_is_output
)

function AsapInstructionKeyword(;
        op = NOP,
        dest = Loc(),
        src1 = Loc(),
        src2 = Loc(),
        nops = zero(Int8),
        jump = false,
        isreturn = false,
        cxflag = NO_CX,
        cxindex = zero(Int8),
        sw = true,
        signed = false,
        saturate = false,
        optype = NOP_TYPE,
        dest_is_output = false
    )

    return AsapInstruction(
        op, 
        dest, src1, src2,
        nops, jump, isreturn,
        cxflag, cxindex,
        sw, signed, saturate,
        optype,
        dest_is_output,
    )
end

abstract type Mutator{T} end

immutable SrcDestCollection <: Mutator{AsapInstruction}
    dest        :: Loc
    src1        :: Loc
    src2        :: Loc
end

immutable InstSrc1 <: Mutator{AsapInstruction}
    src1 :: Loc
end
immutable InstSrc2 <: Mutator{AsapInstruction}
    src2 :: Loc
end
immutable InstDest <: Mutator{AsapInstruction}
    dest :: Loc
end

# Here's a method to change the src's and dest of an instruction quickly 
# (using only the positional constructor rather than one generated by @with_kw)
#
# This is helpful for Stage 2 where pointers are dereferenced and turned into
# memory locations.
#
# Make this a @generated function so it keeps working even if the other fields
# of the AsapInstruction change.
@generated function set(a::T, b::U) where U <: Mutator{T} where T
    # Get the fieldnames for the two arguments.
    a_fields = fieldnames(T)
    b_fields = fieldnames(U)

    # Build up a list of arguments for a positional constructor of AsapInstruction
    # by iterating ove inst_fields. If a given field is in the SrcDestCollection,
    # use that instead.
    args = map(a_fields) do f
        i = findfirst(b_fields, f)
        # If "i" is in the operands fields, return that field.
        return i > 0 ? :(b.$f) : :(a.$f)
    end

    return :(T($(args...)))
end

# Alias "NOP" to an empty constructor, which should provide a NOP by default.
const InstNOP = AsapInstruction


# Methods on instructions - Since some values may be stored in some 
# less-than-obvious places, use these methods to get these fields if needed.

# Get branch-target - This is encoded in the "dest_val" field of the branch
# instructions.
function branch_target(i::AsapInstruction) 
    # For debugging, ensure that this is only called on branch instructions.
    # If not, something ahs gone wrong.
    @assert i.op == BR || i.op == BRL
    return ind(i.dest)
end

# For repeat start, use src2_index. src1_index may be used if the RPT instruction
# uses a dmem or other source
repeat_start(i::AsapInstruction) = ind(i.src2)

# Similarlym, use the dest_index for the repeat end.
repeat_end(i::AsapInstruction) = ind(i.dest)

set_branch_target(t,x) = InstDest(Loc(t,x))
set_repeat_start(x) = InstSrc2(Loc(x))
set_repeat_end(x) = InstDest(Loc(x))
