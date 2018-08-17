#=
Macro for taking normal Julia-like functions of Pseudo Assembly and emitting
a vector of AsapInstructions.

This will probably be a multi-pass operation, where first the expression tree
of the function is converted into AsapInstructions with reckless abandon, and
then several processing steps to check if any assembly instructions were 
provided incorrectly, if the source/destinations are invalid, etc.
=#

macro asap4asm(expr)
    return esc(convertcode(expr))
end

# Convenience functions for converting symbols to either all caps or all 
# lowercase.
symbol_uc(x::Symbol) = Symbol(uppercase(string(x)))
symbol_lc(x::Symbol) = Symbol(lowercase(string(x)))

# Need to make this mutable since we will potentially modifying and changing
# some instructions before separating the instructions and labels.
mutable struct InstructionLabelTarget
    instruction   :: AsapInstruction
    label         :: Union{Symbol,Nothing}
    branch_target :: Union{Symbol,Nothing}
end

function convertcode(expr::Expr)
    # This macro does the following:
    # 1. Extracts the body of the passed function using MacroTools' excellent
    #    "splitdef" function.
    # 2. Drop in an empty Vector{InstructionLabelTarget} at the beginning of
    #    the function.
    # 3. Walk through the body of the function in order, recording the labels
    #    it sees and converting pseudo-assembly function calls into 
    #    InstructionLabelTarget and appending them to the vector.
    # 4. Replace each return by passing the Vector{InstructionLabelTarget} with
    #    a call to an "assembler" function that will analyze the code to resolve
    #    labels and RPT instructions before returning a final program as a
    #    Vector{AsapInstruction}

    # 1 - split function.
    split_expr = splitdef(expr)
    function_body = split_expr[:body]

    # 2 - generate a symbol for the intermediate program and insert it into the
    # beginning of the function body.
    program_vector_sym = gensym("program")
    startvector!(function_body, program_vector_sym)

    # 3 - Replace all instructions with "push!" to the program_vector.
    function_body = replace_instructions(function_body, program_vector_sym)

    # 4 - Replace "return" statements with calls to the assembler.
    # Insert a return statement at the end as well as a default catch.
    function_body = replace_returns(function_body, program_vector_sym) 

    # Rebuild the function and return the modified source code.
    split_expr[:body] = function_body
    return MacroTools.combinedef(split_expr)
end

# Put the expression
#
# program = InstructionLabelTarget[]
#
# At the beginning of the function body - expept that "program" is some 
# complicated thing given by "gensym" so we don't have to worry about it 
# clobbering anything in the function.
function startvector!(function_body :: Expr, program_vector_sym)
    pushfirst!(function_body.args, :($program_vector_sym = InstructionLabelTarget[]))
end

# Container for holding kwargs to give to the Keyword constructor of 
# AsapInstruction for a given instruction.
#
# Since I changed from using Symbols to encode Source/Destination locations
# to an Enum, the branch_target can no longer be stored in the instruction
# itself. Thus, we have to record branch targets as a separate field in this
# container.
mutable struct KwargHolder
    kwargs          :: Vector{Pair{Symbol,Any}}
    branch_target   :: Union{Symbol,Nothing}
end
KwargHolder() = KwargHolder(Pair{Symbol,Any}[], nothing)

function replace_instructions(function_body :: Expr, program_vector_sym)
    # Record the last seen label. Attach this to all found assembly instructions.
    #
    # MacroTools.postwalk will encounter expressions in program order, so it is
    # sufficient to keep track of the most recently seen label.
    #
    # When assembling, the label will be resolved to the first instruction that
    # has that label.
    label :: Union{Symbol,Nothing} = nothing

    # Walk through the expression - replacing pseudo-assembly with parsed
    # instruction types.
    new_body = MacroTools.postwalk(function_body) do ex
        if @capture(ex, op_(args__))
            # Check if the name of the function being called is a Assembly
            # instruction. If not - leave it alone.
            if isop(op)
                # Parse the arguments for this operation. Expect to recieve a
                # vector of Pair{Symbol,Any} that represent the arguments to
                # be passed to an AsapInstructionKeyword constructor.
                holder = getkwargs(op, args)

                # Check if branch target is in here. If so, extract it and 
                # record it.
                kwargs = [Expr(:kw, p[1], p[2]) for p in holder.kwargs]
                branch_target = holder.branch_target

                # Create an expression pushing the pair of this label and
                # a AsapInstruction to the program vector.
                new_ex = :(push!(
                     $program_vector_sym,
                     InstructionLabelTarget(
                        AsapInstructionKeyword(;$(kwargs...)),
                        $(Meta.quot(label)),
                        $(Meta.quot(branch_target)),
                     )))

                # replace the expression
                return new_ex
            end

        # Record macro calls
        # The item returned by the @capture will be either a QuoteNode or
        # a Symbol. For consistency sake, always turn it into a Symbol.
        #
        # It seems that code captured from the REPL will be lowered to a Symbol
        # while code lowered from a file yields a QuoteNode. Not entirely sure
        # what is going on there.
        elseif @capture(ex, @label label_quotenode_or_symbol_)
            label = Symbol(label_quotenode_or_symbol)
            # Replace the label with nothing - removing it from the code.
            return nothing
        end

        # Default fallback - return expression unchanged.
        return ex
    end

    return new_body
end

# Helper macro.
macro pairpush!(kwargs, syms...)
    symmaps = [:($(Meta.quot(sym)) => $sym) for sym in syms]
    return esc(:(push!($kwargs, $(symmaps...))))
end

function getkwargs(op, args)
    # Need to get a collection of keyword arguments to give to the caller for
    # this operation and arguments.
    holder = KwargHolder()
    push!(holder.kwargs, :op => :(AsapSim.$op))

    # Get the InstructionDefinition for this operation.
    def = getdef(op)

    # Hendle special instrucitons first.
    if op == :BR || op == :BRL
        # Get the destination label
        destination_label = first(args)

        # Add the branch target to the front of the vector. Upper level routine
        # will extract it.
        holder.branch_target = destination_label

        # Record if this is a return.
        if destination_label == :back
            push!(holder.kwargs, :isreturn => true)
        end

        # Remove the destination argument from the vector to avoid using it
        # more than once.
        popfirst!(args)

        # (TODO) - this is temporary. Need to really first perform a check to
        # see if the caller is providing branch options. Otherwise, need to be
        # a little more precise with how this is handled
        push!(holder.kwargs, :src1 => Loc(IMMEDIATE, make_branch_mask(args)))

        # Get options for this instruction.
        append!(holder.kwargs, getoptions(args))

    # General instruction decoding.
    else
        # If this instruction definition has a destination - extract it and
        # remove the destination from the argument list.
        if def.dest
            dest = extract_loc(first(args))
            @pairpush! holder.kwargs dest
            popfirst!(args)
        end

        # Parse out src1 and src2
        if def.src1
            src1 = extract_loc(first(args))
            @pairpush! holder.kwargs src1
            popfirst!(args)
        end
        if def.src2
            src2 = extract_loc(first(args))
            @pairpush! holder.kwargs src2
        end

        # Get options for this instruction.
        append!(holder.kwargs, getoptions(args))
    end

    # Mark the op type and special attributes.
    push!(holder.kwargs, :optype => def.optype)
    if def.signed
        push!(holder.kwargs, :signed => true)
    end
    if def.saturate
        push!(holder.kwargs, :saturate => true)
    end
    return holder
end

extract_loc(val::Integer) = :(Loc(AsapSim.IMMEDIATE, $val))
function extract_loc(sym::Symbol) 
    # Convert the symbol to all uppercase letters for matching with the
    # enumerated source/destination locations.
    sym_upper = symbol_uc(sym)

    # If this symbol is a valid source or destination keyword, return the 
    # constructor for a Loc based on the SrcDest enum.
    #
    # Prefix it with "AsapSim" to avoid scoping issues.
    if sym_upper in SourceDestSymbols
        return :(Loc(AsapSim.$sym_upper))

    # Otherwise, check if this is a common keyword. If so, pass the symbol
    # directly to the constructor 
    #
    # i.e., extract_loc(:ibuf0) == :(Loc(:ibuf0))
    elseif sym in keys(SourceAliases)
        return :(Loc($(Meta.quot(sym))))

    # Otherwise, assume that this is some call-time construct and don't modify
    # the argument at all.
    else
        return :(Loc($sym))
    end
end


function extract_loc(expr::Expr)
    # Check if this expression is a :ref expression (like "dmem[0]"), if so
    # return the two args (i.e. :dmem and 0)
    if @capture(expr, sym_[ind_])
        sym_upper = symbol_uc(sym)
        if sym_upper in SourceDestSymbols
            return :(Loc(AsapSim.$sym_upper, $ind))
        else
            return :(Loc($expr))
        end

    # Otherwise, assume this expression is some computation for an immediate
    # and pass the whole expression.
    else
        return :(Loc($expr))
    end
end

function replace_returns(function_body, program_vector_sym; return_fn = :assemble)
    # Create the expression to replace the returns with.
    new_ex = :(return $return_fn($program_vector_sym))

    # Add an empty return at the end of the function body.
    # This will get replaced with the above expression during the pass below.
    push!(function_body.args, :(return))

    # Postwalk again, replace returns.
    new_body = MacroTools.postwalk(function_body) do ex
        if @capture(ex, return args__)
            # TODO: Maybe give error if there are arguments other than "nothing"
            return new_ex
        end

        # Default return
        return ex
    end

    return new_body
end

# Function for constructing the immediate mask for the branch instruction.
function make_branch_mask(args)
    # Iterate through the arguments in the order the bits are set for convenience.
    possible_args = (:N, :Z, :C, :O, :F0, :F1, :PI, :PO, :OB, :MI, :MO, :U, :neg)

    mask = 0

    for (bit, arg) in enumerate(possible_args)
        indices = findall(x -> x == arg, args)
        # Check if this argument exists. If so, set the corresponding bit of the
        # mask.
        if length(indices) > 0
            mask |= 1 << (bit - 1)
            # Delete this entry in the args.
            deleteat!(args, indices)
        end
    end

    # Check if the mask is still zero, if so, set the unconditional bit of the
    # mask.
    if mask == 0
        mask |= 1 << 11
    end
    return mask
end

function make_stall_mask(args)
    # Similar to branch mask.
    possible_args = (
        :ibuf0, 
        :ibuf1, 
        :packet_in, 
        :memory_in, 
        :obuf_full,
        :packet_out,
        :memory_out,
    )

    for (bit, arg) in enumerate(possible_args)
        indices = find(x -> x == arg, args)
        if length(indices) > 0
            mask |= 1 << (bit - 1)
            deleteat!(args, indices)
        end
    end

    # No default bit needs to be set for the stall mask.
    return mask
end
