@testset "Testing Sort" begin
    # Need to pass 50 words at a time as records. First 5 words are the key
    # and the last 45 words are the payload.

    # Instantiate a core. For now, only test a single core, so mark it as both 
    # the first and the last core.


    # Create three 50 word records.
    makerecord = TestPrograms.makerecord
    records = [makerecord(i, zerofirst = true) for i in 1:3]

    # In all cases, the output result should be the record with the minimujm
    # key.
    #
    # Make sure to strip off the leading 1.
    expected_result = records[1][2:end]

    # We're going to feed these into the test core in all permutations of the
    # three records. In each case, the record with Key 0 0 0 0 1 should come out
    # since it has the lowest key.
    perms = (
        [1, 2, 3],
        [1, 3, 2],
        [2, 1, 3],
        [2, 3, 1],
        [3, 1, 2],
        [3, 2, 1],
    )

    for perm in perms
        core = testfifo_core(TestPrograms.snakesort(true, true, false))
        TestPrograms.initialize_snakesort(core)


        # Create an output to attach to the core.
        output = AsapSim.TestFifo{Int16}()
        core.outputs[1] = output
        # Index the "records" vector according to the permutation chosen.
        core.fifos[1].read_data = vcat(records[perm]...)

        # Run this test until 50 bytes of data has been recieved or until timeout.
        @time runfor(core, 1000)
        @test output.write_data == expected_result
    end
end

@testset "Testing SnakeSort" begin
    # Test a system consisting of
    # input -> sort -> sort -> sort -> sort -> output
    #
    # This will test all of the sort variations.
    srand(2)

    num_records = 8
    records = [TestPrograms.makerecord(i, zerofirst = true) for i in 1:num_records]

    # Expected results are these records in order - strip the learding zeros.
    expected_results = vcat((r[2:end] for r in records)...)

    # Iterate through several permutations.
    failing_permutations = []

    for _ in 1:50
        # Generate a random permutatation for the records.
        perm = randperm(num_records)

        # Create 4 sort cores.
        #
        # NOTE: These could be put in a vector and a lot of this done 
        # automatically. I'm doing it by hand just for clarity sake.
        core_1 = test_core(TestPrograms.snakesort(true, false, false))
        core_2 = test_core(TestPrograms.snakesort(false, false,false))
        core_3 = test_core(TestPrograms.snakesort(false, false, false))
        core_4 = test_core(TestPrograms.snakesort(false, true, false))

        # Initialize all cores.
        TestPrograms.initialize_snakesort(core_1)
        TestPrograms.initialize_snakesort(core_2)
        TestPrograms.initialize_snakesort(core_3)
        TestPrograms.initialize_snakesort(core_4)

        # Connect outputs to inputs.
        core_1.outputs[1] = core_2.fifos[1]
        core_1.outputs[2] = core_2.fifos[2]

        core_2.outputs[1] = core_3.fifos[1]
        core_2.outputs[2] = core_3.fifos[2]

        core_3.outputs[1] = core_4.fifos[1]
        core_3.outputs[2] = core_4.fifos[2]

        # Create a fifo for the output handler
        output_fifo = AsapSim.DualClockFifo(Int16, 32)
        output_handler = AsapSim.OutputHandler{Int16, typeof(output_fifo)}(
            input = output_fifo
        )
        core_4.outputs[1] = output_fifo

        # Create an input handler and connect it to the ibuf of core 1
        input_handler = AsapSim.InputHandler{Int16,typeof(output_fifo)}(
            # End data with -1 to tell first core that we're done.
            data = vcat(records[perm]..., [-1, num_records]),
            output = core_1.fifos[1],
        )

        # Clock the whole system several times.
        for i in 1:2000
            update!(output_handler)
            update!(core_4)
            update!(core_3)
            update!(core_2)
            update!(core_1)
            update!(input_handler)
        end

        passed = output_handler.data == expected_results
        @test passed
        if !passed
            push!(failing_permutations, perm)
        end

        @test length(output_handler.data) == length(expected_results)
    end

    # Print out failing permutations if any were encountered.
    if length(failing_permutations) > 0
        display(failing_permutations)
    end
end
