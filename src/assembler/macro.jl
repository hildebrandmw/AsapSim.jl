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

"""
    asap4asm(code)

Asap assembly instructions will be encoded as a sequence of pseudo-assembly
function calls. For example:

```julia
function test()
    @label :start
    ADD(dmem[0], dmem[1], 10)
    BR(:start, U)
end
```

"""
function convertcode(expr::Expr)
    # Need to do several processing steps.
    # 1. Walk through the code and find all Pseudo-assembly function calls and 
    #    arguments, emit these as a vector of AsapIntermediate instructions
    #
    # 2. Find all "END_RPT" blocks, encode their address in their parent
    #    "RPT" instruction and remove them from the instruction vector
    #
    # 3. Resolve branch targets to addresses, which will just be an index into
    #    the instruction vector.
    #
    # 4. Walk the expression tree again, replacing all pseudo-assembly 
    #    instructions with constrctors for AsapInstructions. Note, we do this
    #    step to preserve line numbers for errors. If a user has some kind of
    #    computation for an immediate that errors, error should preserve line 
    #    number and filename for easier debugging.
    #
    # 5. Return the new code to the caller for execution.

    # Split up the function into pieces.
    split_expr = splitdef(expr)
    # Extract intermediate instructions from the body of the code.
    # 
    # Need to call "unblock" from the body of the function to handle the case
    # where a program only have 1 instruction.
    intermediate_instructions = getassembly(MacroTools.unblock(split_expr[:body]))
    # Encode the repeat blocks and remove the "END_RPT" instructions so 
    # addresses in the final vector are complete.
    handle_rpt!(intermediate_instructions)

    # Create full instructions from the intermediate instructions.
    # This step through the intermediate instructions is important for
    # getting labels recorded correctly.
    instructions = expand(intermediate_instructions)

    # TODO: Eventually want to replace this with a move elegent method of
    # adding each instruction individually to the vector to allow for assembly
    # programs to include their own local definitions for immediates. However,
    # this works for now as a simple technique.
    return MacroTools.@q function $(split_expr[:name])()
        return [$(instructions...)]
    end
end

# Recursive function for gathering line numbers and first-pass instruction 
# parsing.
function getassembly(expr)
    instructions = AsapIntermediate[]

    # Set line and file variables to null values. Will get filled in as these
    # objects are discovered while walking the expression tree.
    line = -1
    file = :null
    label = nothing

    # This is constant and won't change in this function - it's changed later.
    # However, for clarity, define it here.
    repeat_start = nothing
    repeat_end = nothing

    # Call "postwalk" on the expression. This will visit the leaves of the 
    # expression tree first, presumably from top to bottom, which is the order
    # we want.

    # NOTE: postwalk will walk the whole expression tree, which may lead to
    # suboptimal performance as the expression trees grow large. We may be
    # able to optimize this by only walking through a subset of the whole
    # tree on not recursively growing the search like a whole postwalk does.
    MacroTools.postwalk(expr) do ex
        # Check if this is a line number. If so, record it to the "line" and
        # "file" variables so they can be stored with the next emitted 
        # instruction for error messages.
        if MacroTools.isexpr(ex, :line)
            # The expression for the line looks as follow:
            # Expr
            #   head: Symbol line
            #   args: Array{Any}((2,))
            #     1: Int64 3
            #     2: Symbol REPL[2]
            #   typ: Any
            line = ex.args[1]
            file = ex.args[2]

        # Check if this is a function call. If so, slurp up all of the arguments
        # and emit a new instruction
        elseif @capture(ex, op_(args__))
            # Skip calls to functions that are not in the provided opcodes.
            # This help keep things like arithmetic for immediates.
            if isop(op)
                new_instruction = AsapIntermediate(
                    op, 
                    args, 
                    label, 
                    repeat_start, 
                    repeat_end, 
                    file, 
                    line
                )

                push!(instructions, new_instruction)

                # Clear the metadata to prepare for next instructions.
                line = -1
                file = :null
                label = nothing
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
        end

        # Return the sub-expression unchanged to avoid mutating the expression.
        return ex
    end

    # Return vector of instructions.
    return instructions
end


function handle_rpt!(intermediates::Vector{AsapIntermediate})
    # Iterate through each element of the intermediate instructions. 
    index_of_last_rpt = 0
    index = 1
    while index <= length(intermediates)
        if intermediates[index].op == :END_RPT
            # Save the index of the instruction before this as the end of the
            # repeat block and delete this op from the instruction vector.
            intermediates[index_of_last_rpt].repeat_end = index - 1

            # In this case, don't increment "index" because it will 
            # automatically point to the next instruction since we deleted
            # :END_RPT
            deleteat!(intermediates, index)
        elseif intermediates[index].op == :RPT
            # Set the start point for this repeat. Since we've removed all
            # END_RPT before this, we don't have to worry about this index
            # getting messed up. 
            #
            # Add 1 so the start points to the next instruction.
            intermediates[index].repeat_start = index + 1

            # Mark the index of the last repeat function for fast setting.
            index_of_last_rpt = index
            index += 1
        else
            index += 1
        end
    end
end

"""
    expand(intermediate::Vector{AsapIntermediate})

Return the full form of the intermediate instructions.
"""
function expand(intermediates::Vector{AsapIntermediate})
    # Step 1: Find the location of all labels in the intermediate program.
    label_dict = findlabels(intermediates)
    # Step 2: Iterate through each instruction, expand to the full instruction
    # based on the opcode.
    instructions = map(intermediates) do i
        pairs = expand(i, label_dict)
        # Create the keyword arguments for an AsapInstruction from the returned
        # pairs.
        kwargs = map(pairs) do p
            key = p[1]
            value = p[2]
            # Have to build these expression manually with the :kw head because 
            # doing :($kev = $value) is interpreted as some kind of assignment
            # rather than passing a keyword argument.
            if value isa Symbol
                return Expr(:kw, key, Meta.quot(value))
            else
                return Expr(:kw, key, value)
            end
        end
        return :(AsapInstruction(;$(kwargs...)))
    end

    return instructions
end

"""
    findlabels(x::Vector{AsapIntermediate})

Return a Dict{Symbol,Int64} with keys that are the symbols of labels in the
intermediate code and whose values are the indices of instructions with those
labels.
"""
findlabels(x::Vector{AsapIntermediate}) = 
    Dict(k.label => i for (i,k) in enumerate(x) if k.label isa Symbol)

macro pairpush!(kwargs, syms...)
    symmaps = [:($(Meta.quot(sym)) => $sym) for sym in syms]
    return esc(:(push!($kwargs, $(symmaps...))))
end

function expand(inst::AsapIntermediate, label_dict)
    # Key-word arguments to pass to the constructor for the instruction.
    kwargs = Vector{Pair{Symbol,Any}}([:op => inst.op])

    # Get the InstructionDefinition for this operation.
    def = getdef(inst.op)

    # Decode the instruction.
    # Handle special cases first:

    # TODO: Rethink how to encode STALLS
    if inst.op == :BR || inst.op == :BRL
        # Set the source to an immediate
        push!(kwargs, :src1 => :immediate)
        # Build the mask for the immediate
        push!(kwargs, :src1_index => make_branch_mask(inst.args))
        # Get the index for the destination from the label dictionary
        push!(kwargs, set_branch_target(label_dict[Symbol(inst.args[1])]))

        # Get the rest of the options for this instruction.
        append!(kwargs, getoptions(inst.args[2:end]))

    # General instruction decoding.
    else
        # If this instruction definition has a destination, extract that
        # destination and remove it from the argument list.
        if def.dest
            dest, dest_index = extract_ref(first(inst.args))
            @pairpush! kwargs dest dest_index
            shift!(inst.args)

            # Check if the destination is a core output. If so, mark this
            # instruction.
            if dest in DestinationOutputs
                push!(kwargs, (:dest_is_output => true))
            end
        end

        # Parse out src1
        if def.src1
            src1, src1_index = extract_ref(first(inst.args))
            @pairpush! kwargs src1 src1_index
            shift!(inst.args)
        end

        # Parse out src2
        if def.src2
            src2, src2_index = extract_ref(first(inst.args))
            @pairpush! kwargs src2 src2_index
            shift!(inst.args)
        end

        # Get the options for this instruction.
        append!(kwargs, getoptions(inst.args))

        # Handle special instructions
        if inst.op == :RPT
            push!(kwargs, set_repeat_start(inst.repeat_start))
            push!(kwargs, set_repeat_end(inst.repeat_end))
        end
    end

    # Mark op-type and some special properties.
    push!(kwargs, :optype => def.optype)
    if def.signed
        push!(kwargs, :signed => true)
    end
    if def.saturate
        push!(kwargs, :saturate => true)
    end
    return kwargs
end

# Helper functions

# Cases where an immediate is given - set the symbol to "immediate" and store
# the value of the immediate as the "value" of the source or destination.
extract_ref(val::Integer) =  (:immediate, val)

# If just a symbol is given, store that symbol and give a "value" of -1.
extract_ref(sym::Symbol) =  (sym, -1)

# Fallback case, store the symbol of the reference and the index as the "value"
function extract_ref(expr::Expr)
    # Check if this expression is a :ref expression (like "dmem[0]"), if so
    # return the two args (i.e. :dmem and 0)
    if expr.head == :ref
        # TODO: check if the first argument is in one of the proper destination
        # arguments. If it isn't, throw an error?
        return (expr.args[1], expr.args[2])

    # Otherwise, assume this expression is some computation for an immediate
    # and pass the whole expression.
    else
        return (:immediate, expr)   
    end
end

# Function for constructing the immediate mask for the branch instruction.
function make_branch_mask(args)
    # Iterate through the arguments in the order the bits are set for convenience.
    possible_args = (:N, :Z, :C, :O, :F0, :F1, :PI, :PO, :OB, :MI, :MO, :U, :neg)

    mask = 0

    for (bit, arg) in enumerate(possible_args)
        indices = find(x -> x == arg, args)
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

# Accessors for reading stall bits.
stall_empty_ibuf0(inst::AsapInstruction)    = inst.src1_index & (1 << 0) != 0
stall_empty_ibuf1(inst::AsapInstruction)    = inst.src1_index & (1 << 1) != 0
stall_empty_packet(inst::AsapInstruction)   = inst.src1_index & (1 << 2) != 0
stall_empty_mem(inst::AsapInstruction)      = inst.src1_index & (1 << 3) != 0
stall_full_packet(inst::AsapInstruction)    = inst.src1_index & (1 << 4) != 0
stall_full_mem(inst::AsapInstruction)       = inst.src1_index & (1 << 5) != 0
stall_full_obuf(inst::AsapInstruction)      = inst.src1_index & (1 << 6) != 0
