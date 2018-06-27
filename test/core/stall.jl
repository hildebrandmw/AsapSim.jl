# Test suite for testing stall logic.
#
# Strategy: Use "TestFifos" to do dependency injection to test the logic of
# the stall suites. This still involves creating a whole "AsapCore", but we
# will have much better control over the state of the various fifos for
# testing.
@testset "Testing Stall Logic" begin
    TestFifo = AsapSim.TestFifo

    num_outputs = 8

    # Instantiate a specializd core.
    core = AsapSim.AsapCore{EmptyFullFifo}(
        clock_period = 1,
        fifos = [EmptyFullFifo(), EmptyFullFifo()],
        # Populate all 8 output directions.
        outputs = Dict{Int,EmptyFullFifo}(i => EmptyFullFifo() for i in 1:num_outputs)
    )

    # ------------------------------- #
    # --- Test normal IO stalling --- #
    # ------------------------------- #

    # Set all obuf mask bits to 1. For normal instructions, should not stall
    # right now because all EmptyFullFifo are neither empty nor full.
    core.obuf_mask = trues(8)

    @test AsapSim.stall_check_ibuf(core, 1, false) == false
    @test AsapSim.stall_check_ibuf(core, 2, true) == false

    @test AsapSim.stall_check_obuf(core, 1, false) == false
    @test AsapSim.stall_check_obuf(core, 8, true) == false

    # Make a test instruction reading from both input fifos and writing to
    # an output fifo.
    test_instruction = AsapSim.AsapInstructionKeyword(
        src1 = Loc(:ibuf, 0),
        src2 = Loc(:ibuf_next, 1),
        dest = Loc(:output, 0),
    )

    # Since all FIFOs are ready to go, core should not stall.
    @test AsapSim.stall_check_io(core, test_instruction) == false

    # Start iterating over fifos, first setting inputs to "empty", then output
    # to "full". Make sure that stall logic fires correctly.
    core.fifos[1].empty = true
    @test AsapSim.stall_check_io(core, test_instruction) == true

    core.fifos[1].empty = false
    core.fifos[2].empty = true
    @test AsapSim.stall_check_io(core, test_instruction) == true

    core.fifos[2].empty = false
    core.outputs[1].full = true
    @test AsapSim.stall_check_io(core, test_instruction) == true

    core.outputs[1].full = false

    # New test instruction testing the broadcast mechanism.
    test_instruction = AsapSim.AsapInstructionKeyword(
        dest = :obuf
    )

    # Right now, all outputs are not full, so stall should not be triggered.
    @test AsapSim.stall_check_io(core, test_instruction) == false

    core.outputs[8].full = true
    @test AsapSim.stall_check_io(core, test_instruction) == true

    core.outputs[8].full = false
    core.outputs[5].full = true
    @test AsapSim.stall_check_io(core, test_instruction) == true

    core.outputs[5].full = false

    # Iterate through all output buffers.
    # Set each output to full in turn but deactivate the mask bit for that 
    # output.
    # 
    # Core should not stall.
    for i in 1:num_outputs
        core.outputs[i].full = true
        core.obuf_mask[i] = false
        @test AsapSim.stall_check_io(core, test_instruction) == false

        # Reset for next test.
        core.outputs[i].full = false
        core.obuf_mask[i] = true
    end

    # Do this again, but deactivate all mask bits first.
    #
    # Then, set each output to "full" and its corresponding mask bit high.
    #
    # Should stall in each case.

    # Set all mask bits to false.
    core.obuf_mask .= false
    for i in 1:num_outputs
        core.outputs[i].full = true
        core.obuf_mask[i] = true
        @test AsapSim.stall_check_io(core, test_instruction) == true

        core.outputs[i].full = false
        core.obuf_mask[i] = false
    end

    # ------------------------------ #
    # --- Test STALL instruction --- #
    # ------------------------------ #

    # Reset the state of all fifos.
    for fifo in core.fifos
        fifo.empty = true
    end

    for fifo in values(core.outputs)
        fifo.full = true
    end
    core.obuf_mask .= true

    # Create a mask checking all IO.
    all_mask = 0b10011

    # Stall should return "true" since all inputs are empty and all outputs
    # are full.
    @test AsapSim.stall_check_stall_op(core, all_mask) == true

    # Iterate over inputs, setting each non-empty. Test that the core should
    # not stall. Then do the same for the outputs.
    for fifo in core.fifos
        fifo.empty = false
        @test AsapSim.stall_check_stall_op(core, all_mask) == false
        fifo.empty = true
    end

    for fifo in values(core.outputs)
        fifo.full = false
        @test AsapSim.stall_check_stall_op(core, all_mask) == false
        fifo.full = true
    end

    # Only check outputs, but make inputs non-empty.
    for fifo in core.fifos
        fifo.empty = false
    end

    output_mask = 0b10000
    @test AsapSim.stall_check_stall_op(core, output_mask) == true

    # Do similar checking of the output mask as we did for the IO Stall above.
    core.obuf_mask .= true
    for fifo in values(core.outputs)
        fifo.full = true
    end

    # Ignore non-full fifos. Should always stall.
    for i in 1:num_outputs
        core.outputs[i].full = false
        core.obuf_mask[i] = false
        @test AsapSim.stall_check_stall_op(core, output_mask) == true

        core.outputs[i].full = true
        core.obuf_mask[i] = true
    end

    # Flip the state of everything.
    core.obuf_mask .= false
    for fifo in values(core.outputs)
        fifo.full = true
    end

    for i in 1:num_outputs
        core.outputs[i].full = true
        core.obuf_mask[i] = true
        @test AsapSim.stall_check_stall_op(core, output_mask) == true

        core.outputs[i].full = false
        core.obuf_mask[i] = false
    end
end
