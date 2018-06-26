@testset "Testing Sort" begin
    function runfor(c, n) 
        for _ in 1:n
            AsapSim.update!(c)
        end
    end

    function writeto(fifo, payload, index)
        while AsapSim.iswriteready(fifo) && index <= length(payload)
            write(fifo, payload[index])
            AsapSim.writeupdate!(fifo)
            index += 1
        end
        return index
    end

    function readfrom!(fifo, buffer)
        while AsapSim.isreadready(fifo)
            push!(buffer, read(fifo))
            AsapSim.readupdate!(fifo)
        end
    end

    # Need to pass 50 words at a time as records. First 5 words are the key
    # and the last 45 words are the payload.

    # Instantiate a core. For now, only test a single core, so mark it as both 
    # the first and the last core.
    core = test_core(TestPrograms.snakesort(true, true, false))
    TestPrograms.initialize_snakesort(core)

    # Create three 50 word records.
    record_1 = append!(Int16.([0,0,0,0,1]), rand(Int16, 45))
    record_2 = append!(Int16.([0,0,0,0,2]), rand(Int16, 45))
    record_3 = append!(Int16.([0,0,0,0,3]), rand(Int16, 45))

    # Concatenate all of the payloads together
    payload = vcat(0, record_1, 0, record_2, 0, record_3)
    payload_index = 1

    readdata = Int16[]

    # Create an output to attach to the core.
    output = AsapSim.DualClockFifo(Int16, 32)
    core.outputs[1] = output
    input = core.fifos[1]

    # Run this test until 50 bytes of data has been recieved or until timeout.
    count = 0
    while count < 100 && length(readdata) < 50
        # Write data to the input fifo.
        payload_index = writeto(input, payload, payload_index)
        runfor(core, 200)
        readfrom!(output, readdata)

        count += 1
    end

    @show readdata

end
