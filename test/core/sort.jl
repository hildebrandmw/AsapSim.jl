@testset "Testing Sort" begin
    # Need to pass 50 words at a time as records. First 5 words are the key
    # and the last 45 words are the payload.

    # Instantiate a core. For now, only test a single core, so mark it as both 
    # the first and the last core.
    for _ in 1:2
        core = testfifo_core(TestPrograms.snakesort(true, true, false))
        TestPrograms.initialize_snakesort(core)

        # Create four 50 word records.
        makerecord = TestPrograms.makerecord
        records = [makerecord(i, zerofirst = true) for i in 1:3]

        # Create an output to attach to the core.
        output = AsapSim.TestFifo{Int16}()
        core.outputs[1] = output
        core.fifos[1].read_data = vcat(records...)

        # Run this test until 50 bytes of data has been recieved or until timeout.
        @time runfor(core, 1000)

        @show output.write_data
    end
end
