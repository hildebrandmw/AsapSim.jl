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

This is passed to the macro as an expression tree. Dumping the expression tree
yields:

```julia
Expr
  head: Symbol function
  args: Array{Any}((2,))
    1: Expr
      head: Symbol call
      args: Array{Any}((1,))
        1: Symbol test
      typ: Any
    2: Expr
      head: Symbol block
      args: Array{Any}((3,))
        1: Expr
          head: Symbol macrocall
          args: Array{Any}((2,))
            1: Symbol @label
            2: QuoteNode
              value: Symbol start
          typ: Any
        2: Expr
          head: Symbol call
          args: Array{Any}((4,))
            1: Symbol ADD
            2: Expr
              head: Symbol ref
              args: Array{Any}((2,))
                1: Symbol dmem
                2: Int64 0
              typ: Any
            3: Expr
              head: Symbol ref
              args: Array{Any}((2,))
                1: Symbol dmem
                2: Int64 1
              typ: Any
            4: Int64 10
          typ: Any
        3: Expr
          head: Symbol call
          args: Array{Any}((3,))
            1: Symbol BR
            2: QuoteNode
              value: Symbol start
            3: Symbol U
          typ: Any
      typ: Any
  typ: Any
```

We can walk this expression tree to get:

* The opcode for the assembly instruction
* The sources and destination for the instruction, including whether the source
    or destination includes an index (such as dmem) or is unambiguous (like an
    immediate)
* Any options such as conditional execution that are provided with the 
    instruction.
"""
function convertcode(expr::Expr)
    # Split up the function into pieces.
    split_expr = splitdef(expr)
    # Extract intermediate instructions from the body of the code.
    intermediate_instructions = walkcode(split_expr[:body])
    # Create full instructions from the intermediate instructions.
    # This step through the intermediate instructions is important for
    # getting labels recorded correctly.
    instructions = expand(intermediate_instructions)

    # Create a function with the same name as the original that returns
    # the vector of instructions.
    return_expr = MacroTools.@q function $(split_expr[:name])()
        return $instructions
    end

    return return_expr
end

# Recursive function for gathering line numbers and first-pass instruction 
# parsing.
function walkcode(expr)
    instructions = AsapIntermediate[]

    # Set line and file variables to null values. Will get filled in as these
    # objects are discovered while walking the expression tree.
    line = -1
    file = :null
    label = nothing

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
            if op in opcodes
                new_instruction = AsapIntermediate(op, args, label, file, line)
                push!(instructions, new_instruction)

                # Clear the metadata to prepare for next instructions.
                line = -1
                file = :null
                label = nothing
            end

        # Record macro calls
        elseif @capture(ex, @label lab_)
            # "lab" will be a QuoteNode when it is returned from the @capture
            # macro. Extract the symbol inside by accessing the "value" field.
            label = Symbol(lab)
        end

        # Return the sub-expression unchanged to avoid mutating the expression.
        return ex
    end

    # Return vector of instructions.
    return instructions
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
    instructions = [expand(i, label_dict) for i in intermediates]
end

"""
    findlabels(x::Vector{AsapIntermediate})

Return a Dict{Symbol,Int64} with keys that are the symbols of labels in the
intermediate code and whose values are the indices of instructions with those
labels.
"""
findlabels(x::Vector{AsapIntermediate}) = 
    Dict(k.label => i for (i,k) in enumerate(x) if k.label isa Symbol)

function expand(inst::AsapIntermediate, label_dict)
    # Set the defaults for what to provide to AsapInstruction
    src1 = :none
    src1_val = -1
    src2 = :none
    src2_val = -1
    dest = :none
    dest_val = -1
    options = InstructionOptions()

    # Look at the op code to determine what type of instruciton this is and
    # how to decode it.
    if inst.op in instructions_3operand
        dest, dest_val = extract_ref(inst.args[1])
        src1, src1_val = extract_ref(inst.args[2])
        src2, src2_val = extract_ref(inst.args[3])
        # If optional flags are provided, slurp them up.
        if length(inst.args) > 3
            options = getoptions(inst.args[4:end])
        end
    elseif inst.op in instructions_2operand
        dest, dest_val = extract_ref(inst.args[1]) 
        src1, src1_val = extract_ref(inst.args[2])
    
        if length(inst.args) > 2
            options = getoptions(inst.args[4:end])
        end
    elseif inst.op in instructions_1operand
        src1, src1_val = extract_ref(inst.args[1])
        options = getoptions(inst.args[2:end])

    # Now to look at the more complicated instructions that use masks.
    elseif inst.op in instructions_branch
        # Set the source to an immediate
        src1 = :immediate
        # Build the mask for the immediate
        src1_val = make_branch_mask(inst.args)
        # Get the index for the destination from the label dictionary
        dest = :pc
        dest_val = label_dict[Symbol(inst.args[1])]

        # Get the rest of the options for this instruction.
        options = getoptions(inst.args[2:end])
    else
        error("Unrecognized op: $(inst.op).")
    end

    return AsapInstruction(
        inst.op,
        src1,
        src1_val,
        src2,
        src2_val,
        dest,
        dest_val,
        options
    )

end

# Helper functions

# Cases where an immediate is given - set the symbol to "immediate" and store
# the value of the immediate as the "value" of the source or destination.
extract_ref(val::UInt) = (:immediate, reinterpret(Int, val))
extract_ref(val::Unsigned) = (:immediate, UInt(val))
extract_ref(val::Integer) =  (:immediate, val)

# If just a symbol is given, store that symbol and give a "value" of -1.
extract_ref(sym::Symbol) =  (sym, -1)

# Fallback case, store the symbol of the reference and the index as the "value"
function extract_ref(expr::Expr)
    # Check if this expression is a :ref expression (like "dmem[0]"), if so
    # return the two args (i.e. :dmem and 0)
    if expr.head == :ref
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
