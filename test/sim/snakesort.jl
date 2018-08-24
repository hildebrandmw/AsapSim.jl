@testset "Testing Simple Simulation" begin
    num_cores = 200
    num_records = 2 * num_cores
    records = [TestPrograms.makerecord(i, zerofirst = true) for i in 1:num_records]

    # Expected results are these records in order - strip the learding zeros.
    expected_results = vcat((r[2:end] for r in records)...)

    # Iterate through several permutations.
    failing_permutations = []
    snakesort = TestPrograms.snakesort

    for _ in 1:2

        # Generate a random permutatation for the records.
        perm = randperm(num_records)

        # Create 4 sort cores.
        #
        # NOTE: These could be put in a vector and a lot of this done 
        # automatically. I'm doing it by hand just for clarity sake.
        println("Creating Cores")
        cores = [test_core(snakesort(i == 1, i == num_cores, false)) for i in 1:num_cores]

        # Initialize cores
        println("Initializing Cores")
        for c in cores
            TestPrograms.initialize_snakesort(c)
        end

        # Connect fifos
        println("Connecting Cores")
        for i in 1:num_cores - 1, j in 1:2
            cores[i].outputs[j] = cores[i+1].fifos[j]
        end

        # Create a fifo for the output handler
        output_fifo = AsapSim.DualClockFifo(Int16, 32)
        output_handler = AsapSim.OutputHandler{Int16, typeof(output_fifo)}(
            input = output_fifo,
            stoplength = 50 * num_records
        )
        cores[num_cores].outputs[1] = output_fifo

        # Create an input handler and connect it to the ibuf of core 1
        input_handler = AsapSim.InputHandler{Int16,typeof(output_fifo)}(
            # End data with -1 to tell first core that we're done.
            data = vcat(records[perm]..., [-1, num_records]),
            output = cores[1].fifos[1],
        )

        core_vector = vcat(input_handler, cores, output_handler)

        # Randomize clock periods
        println("Randomizing clock periods")
        for c in core_vector
            c.clockperiod = rand(70:100)
        end

        # Create a vector of SimWrappers for all of these cores.
        println("Wrapping Simulation")
        simtime = 500000 * num_records
        sim = LightDES.Simulation(simtime)

        wrappers = [AsapSim.wrap!(sim, i) for i in core_vector]
        println("Starting Simulation")

        for wrapper in wrappers
            AsapSim.schedule!(sim, wrapper)
        end

        # Clear allocation data for better memory analysis.
        Profile.clear_malloc_data()
        Profile.clear()
        @time run(sim)
        println(now(sim))

        open("profile.txt", "w") do f
            Profile.print(f)
        end

        # for w in wrappers
        #     println(w.visits)
        #     core = w.core

        #     isa(core, AsapSim.AsapCore) || continue

        #     println("Testing input fifos")
        #     for (i, fifo) in enumerate(core.fifos)
        #         println(i, " ", AsapSim.stall_check_ibuf(core, i, false))
        #         println("Num Reads: ", fifo.num_reads)
        #         println("Num Writes: ", fifo.num_writes)
        #     end

        #     println("Testing output fifos")
        #     for (k,v) in core.outputs
        #         println(k, " ", AsapSim.stall_check_obuf(core, k, false))
        #         println("Num Reads: ", v.num_reads)
        #         println("Num Writes: ", v.num_writes)
        #     end
        #     println()
        # end

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
