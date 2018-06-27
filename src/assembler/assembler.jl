include("opcodes.jl")
include("macro.jl")
include("show.jl")

################################################################################
# ASSEMBLER
################################################################################
struct AsapProgram
    instructions :: Vector{AsapInstruction}
    labels       :: Dict{Symbol, Int}
end

AsapProgram() = AsapProgram(AsapInstruction[], Dict{Symbol,Int}())

Base.getindex(p::AsapProgram, i) = p.instructions[i]
Base.length(p::AsapProgram) = length(p.instructions)

function Base.show(io::IO, p::AsapProgram, pc = 0)
    # Reverse the label dict to go from istruction numbers to symbols.
    label_rev = Dict(v => k for (k,v) in p.labels)
    for i in 1:length(p.instructions)
        # Check if this instruction is the start of a label.
        if haskey(label_rev, i)
            println(io, "\n", label_rev[i], ":")
        end

        # Check if PC is here. If so, mark it with an arrow.
        leader = i == pc ? "--> " : "    "
        # Print out instruction.
        println(io, leader, "$i : $(p.instructions[i])")
    end
end

function assemble(temp_program :: Vector{InstructionLabelPair})
    # First - need to take care of END_RPT() instructions.
    handle_rpt!(temp_program)

    # With repeats handled, we aren't removing any more instructions, so we can
    # split apart the labels and the instructions.
    program = [i.instruction for i in temp_program]
    labels = [i.label for i in temp_program]

    # Make a dictionary of the first index where each label is seen.
    labeldict = makelabeldict(labels)

    # Set branch targets
    for (index, inst) in enumerate(program)
        if inst.op == :BR || inst.op == :BRL
            # Get the destination label.
            destination = sym(inst.dest)
            # If this is a "return" - don't do anything
            destination == :back && continue

            # Otherwise, look up its location in the label dict and replace
            # this instruction with a resolved destination.
            branch_target = labeldict[destination]

            program[index] = set(inst, set_branch_target(destination, branch_target))
        end
    end

    return AsapProgram(program, labeldict)
end

function handle_rpt!(program :: Vector{InstructionLabelPair})
    # Iterate through each element of the intermediate instructions.
    index_of_last_rpt = 0
    index = 1
    while index <= length(program)
        # Get the instruction here
        instruction = program[index].instruction
        if instruction.op == :END_RPT
            # Save the index of the instruction before this as the end of the
            # repeat block and delete this op from the instruction vector.
            last_rpt = program[index_of_last_rpt].instruction
            program[index_of_last_rpt].instruction = set(last_rpt, set_repeat_end(index - 1))

            # In this case, don't increment "index" because it will 
            # automatically point to the next instruction since we deleted
            # :END_RPT
            deleteat!(program, index)
        elseif instruction.op == :RPT
            # Set the start point for this repeat. Since we've removed all
            # END_RPT before this, we don't have to worry about this index
            # getting messed up. 
            #
            # Add 1 so the start points to the next instruction.
            program[index].instruction = set(instruction, set_repeat_start(index + 1))

            # Mark the index of the last repeat function for fast setting.
            index_of_last_rpt = index
            index += 1
        else
            index += 1
        end
    end
end

function makelabeldict(labels)
    d = Dict{Symbol,Int}()
    for (index, label) in enumerate(labels)
        # Skip non-set labels
        label isa Void && continue

        # Check if a symbol is already in the dictionary. If so, do nothing.
        # Otherwise, mark this index.
        if !in(label, keys(d))
            d[label] = index
        end
    end
    return d
end
