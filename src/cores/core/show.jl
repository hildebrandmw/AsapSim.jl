showprogram(core::AsapCore) = show(STDOUT, core.program, core.pc)

# Method for quickly summarizing a core.
function summarize(core::AsapCore)
    # Get the stall signals since these are evaluated on each clock cycle and
    # not stored in core state.
    #stall_signals = stall_check(core)

    # Display various processor state.
    show_hwstate(core)
    println()
    show_condexec(core)
    println()
    show_io(core)
    println()
    show_pipeline(core)
end

################################################################################
#                           SHOW ALU FLAGS
################################################################################
function Base.show(io::IO, f::ALUFlags)
    print(io, "ALU Flags: ")
    print(io, "C = $(f.carry), ")
    print(io, "N = $(f.negative), ")
    print(io, "O = $(f.overflow), ")
    print(io, "Z = $(f.zero) ")
end

################################################################################
#                           SHOW PIPELINE ENTRY
################################################################################
function Base.show(io::IO, p::PipelineEntry)
    # Show the instruction.
    show(io, p.instruction)

    # Show the values
    print(io, "src1_v=$(p.src1_value) ")
    print(io, "src2_v=$(p.src2_value) ")
    print(io, "result=$(p.result) ")
end

################################################################################
#                          SHOW ADDRESS GENERATOR
################################################################################
function Base.show(io::IO, ag::AddressGenerator)
    # start:step:stop -- current
    print(io, "$(ag.start):$(ag.stride):$(ag.stop) -- $(ag.current)")
end

################################################################################
#                        SHOW CONDITIONAL EXECUTION
################################################################################
function Base.show(io::IO, c::CondExec)
    print(io, "Flag = $(c.flag), ")
    # Mask has 14 meaningful bits. Show the bits directly.
    print(io, "Mask = $(bits(c.mask)[end - 14:end]), ")
    # Print Reduction
    print(io, "Reduction = $(c.unary_op), ")

    # Interpret the bits for faster decoding.
    mask = c.mask

    # Only print out the summary if there's something to show.
    print(io, "Mask Summary: ")
    isbitset(mask, 13) && print(io, "EK ")
    # Bits 11 and 12 encode the unary op, which is already diaplayed
    isbitset(mask, 10) && print(io, "MO ")
    isbitset(mask,  9) && print(io, "PO ")
    isbitset(mask,  8) && print(io, "OBUF ")
    isbitset(mask,  7) && print(io, "MI ")
    isbitset(mask,  6) && print(io, "PI ")
    isbitset(mask,  5) && print(io, "IBUF1 ")
    isbitset(mask,  4) && print(io, "IBUF0 ")
    isbitset(mask,  3) && print(io, "O ")
    isbitset(mask,  2) && print(io, "C ")
    isbitset(mask,  1) && print(io, "Z ")
    isbitset(mask,  0) && print(io, "N ")
    
end

################################################################################
#                          SHOW PROCESSOR STATE
################################################################################

function show_hwstate(core::AsapCore)
    print_with_color(:white, "HW State\n"; bold = true)
    println("PC: $(core.pc)")

    # Create an auto-align object for printing information horizontally.
    aa = AutoAligns.AutoAlign(align = Dict(:default => AutoAligns.left))

    # Line 1
    print(aa, "Pending Nops: ", core.pending_nops, "   ")
    print(aa, "HW Pointer 0: ", core.pointers[1], "   ")
    print(aa, "AG 0: ", core.address_generators[1], "   ")
    println(aa)

    # Line 2
    print(aa, "Return Address: ", core.return_address, "   ")
    print(aa, "HW Pointer 1: ",   core.pointers[2], "   ")
    print(aa, "AG 1: ", core.address_generators[2], "   ")
    println(aa)

    # Line 3
    print(aa, "Repeat Start: ", core.repeat_start, "   ")
    print(aa, "HW Pointer 2: ", core.pointers[3], "   ")
    print(aa, "AG 2: ", core.address_generators[3], "   ")
    println(aa)

    # Line 4
    print(aa, "Repeat End: ", core.repeat_end, "   ")
    print(aa, "HW Pointer 3: ", core.pointers[4], "   ")
    println(aa)

    # Line 5
    print(aa, "Repeat Count: ", core.repeat_count, "   ")
    println(aa)

    # Print the AutoAlign object
    print(STDOUT, aa)

    # --- ALU Flags and Accumulator --- #
    println()
    println(core.aluflags)
    println()
    println("Accumulator: $(core.accumulator)")
    println()

    # Print out branch mispredict
    if checkbranch(core)
        print_with_color(:red, "Branch Mispredicted\n")
    else
        print_with_color(:green, "No Branch Mispredict\n")
    end

    # Print out stall reason if the core is stalled.
    stall_reason = stall_fifo_check(core)
    if stall_reason != NoStall
        println()
        println("Stall reason: $stall_reason")
    end
end

function show_condexec(core::AsapCore)
    print_with_color(:white, "Conditional Execution\n", bold = true)
    for (index, condexec) in enumerate(core.condexec)
        println("CX$(index-1): $condexec")
    end
end



# Show the status of the input and output fifos.
function show_io(core::AsapCore)
    print_with_color(:white, "Input Fifo Occupancy\n"; bold = true)
    for (index, fifo) in enumerate(core.fifos)
        color = isreadready(fifo) ? :green : :red
        print_with_color(color, "Fifo $(index -1): $(read_occupancy(fifo))\n")
    end

    println()
    print_with_color(:white, "Output Fifo Occupancy\n"; bold = true)
    for (k,v) in core.outputs
        println("Output $k: $(write_occupancy(v))")
    end
    # Declare boldly if no output fifos have been connected.
    if length(core.outputs) == 0
        print_with_color(:red, "No Connected Outputs\n")
    end

    # --- Show the output mask --- #
    println()
    print_with_color(:white, "OBUF Mask\n", bold = true)

    # Convert the obuf mask to a string
    obuf_mask_string = join([x ? "1" : "0" for x in core.obuf_mask])
    println(obuf_mask_string)

    # Print out selected indices for easier viewing.
    for (index, val) in enumerate(core.obuf_mask)
        val && print(io, index-1, " ")
    end
end

# Show the pipeline to STDOUT. Take stall signals as an argument to color
# stages according to if they are stalled or not.
#
# Color has the following meaning:
#
# WHITE: Stage is executing normally
# RED:   Stage is stalled
# CYAN:  Stage is inserting NOPS.
function show_pipeline(core::AsapCore)
    stall_signals = stall_check(core)
    mispredict = checkbranch(core)

    print_with_color(:white, "Pipeline\n"; bold = true)

    # Show stages 0 and 1. For Stage 1, create a pipe stage for the current
    # value of the PC so we can se what's next.
    color = stall_signals.stall_01 ? (:red) : (:white)

    # Print stage 0
    print_with_color(color, "Stage 0: No Instruction\n")

    # Run Stage 0 to get the next program counter.
    s0_nextstate = pipeline_stage0(core, stall_signals.stall_01, mispredict)

    # Create a instruction for stage 1. Make NOP if PC is out of bounds.
    print_with_color(color, "Stage 1: $(core.pipeline.stage1)\n")

    # Select a color for Stage 2
    if stall_signals.stall_234
        color = :red
    elseif stall_signals.nop_2
        color = :cyan
    else
        color = :white
    end
    print_with_color(color, "Stage 2: $(core.pipeline.stage2)\n")

    # Select a color for stages 3 and 4.
    color = stall_signals.stall_234 ? (:red) : (:white)
    print_with_color(color, "Stage 3: $(core.pipeline.stage3)\n")
    print_with_color(color, "Stage 4: $(core.pipeline.stage4)\n")

    # Print stage 5 with its myriad of colors.
    if stall_signals.nop_5
        color = :cyan
    elseif stall_signals.stall_5678
        color = :red
    else
        color = :white
    end
    print_with_color(color, "Stage 5: $(core.pipeline.stage5)\n")

    # Default to Stalled and Unstalled.
    color = stall_signals.stall_5678  ? (:red) : (:white)
    print_with_color(color, "Stage 6: $(core.pipeline.stage6)\n")
    print_with_color(color, "Stage 7: $(core.pipeline.stage7)\n")
end
