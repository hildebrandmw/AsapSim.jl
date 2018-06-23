# Method for quickly summarizing a core.
function summarize(core::AsapCore)
    # Get the stall signals since these are evaluated on each clock cycle and
    # not stored in core state.
    #stall_signals = stall_check(core)

    # Display various processor state.
    show_hwstate(core)
    println()
    show_io(core)
    println()
    show_pipeline(core)
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

    # Print out branch mispredict
    if core.branch_mispredict
        print_with_color(:red, "Branch Mispredicted\n")
    else
        print_with_color(:green, "No Branch Mispredict\n")
    end
end

# Show the status of the input and output fifos.
function show_io(core::AsapCore)
    print_with_color(:white, "Input Fifo Occupancy\n"; bold = true)
    for (index, fifo) in enumerate(core.fifos)
        color = isreadready(fifo) ? :green : :red
        print_with_color(color, "Fifo $(index -1): $(read_occupancy(fifo))\n")
    end

    print_with_color(:white, "Output Fifo Occupancy\n"; bold = true)
    for (k,v) in core.outputs
        println("Output $k: $(write_occupancy(v))")
    end
    # Declare boldly if no output fifos have been connected.
    if length(core.outputs) == 0
        print_with_color(:red, "No Connected Outputs\n")
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

    print_with_color(:white, "Pipeline\n"; bold = true)

    # Show stages 0 and 1. For Stage 1, create a pipe stage for the current
    # value of the PC so we can se what's next.
    color = stall_signals.stall_01 ? (:red) : (:white)

    # Print stage 0
    print_with_color(color, "Stage 0: No Instruction\n")
    # Create a instruction for stage 1. Make NOP if PC is out of bounds.
    if core.pc <= length(core.program)
        s1_stage = PipelineEntry(core, core.program[core.pc])
    else
        s1_stage = PipelineEntry(core, NOP())
    end
    print_with_color(color, "Stage 1: $(s1_stage)\n")

    # Print out stages 2, 3, and 4.
    color = stall_signals.stall_234 ? (:red) : (:white)
    print_with_color(color, "Stage 2: $(core.pipeline.stage2)\n")
    print_with_color(color, "Stage 3: $(core.pipeline.stage3)\n")
    print_with_color(color, "Stage 4: $(core.pipeline.stage4)\n")

    # Print stage 5 with its myriad of colors.
    if stall_signals.nop_5
        color = :cyan
    elseif stall_signals.stall_567
        color = :red
    else
        color = :white
    end
    print_with_color(color, "Stage 5: $(core.pipeline.stage5)\n")

    # Default to Stalled and Unstalled.
    color = stall_signals.stall_567  ? (:red) : (:white)
    print_with_color(color, "Stage 6: $(core.pipeline.stage6)\n")
    print_with_color(color, "Stage 7: $(core.pipeline.stage7)\n")

    # Stage 8 never stalls, just print it white.
    print_with_color(:white, "Stage 8: $(core.pipeline.stage8)\n")
end
