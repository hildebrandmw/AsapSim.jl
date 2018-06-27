@testset "Testing Sort" begin
    function runfor(c, n) 
        for _ in 1:n
            AsapSim.update!(c)
        end
    end

    function writeto!(fifo, payload, index)
        # Need to clock fifo to get it to update.
        for i in 1:AsapSim.buffersize(fifo)
            writeupdate!(fifo)
        end
        while AsapSim.iswriteready(fifo) && index <= length(payload)
            write(fifo, payload[index])
            writeupdate!(fifo)
            index += 1
        end
        return index
    end

    function readfrom!(fifo, buffer)
        for i in 1:AsapSim.buffersize(fifo)
            readupdate!(fifo)
        end
        while AsapSim.isreadready(fifo)
            push!(buffer, read(fifo))
            readupdate!(fifo)
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
    record_4 = append!(Int16.([0,0,0,0,4]), rand(Int16, 45))

    # Concatenate all of the payloads together
    payload = vcat(0, record_1, 0, record_2, 0, record_3, 0, record_4, 0)
    payload_index = 1

    readdata = Int16[]

    # Create an output to attach to the core.
    output = AsapSim.DualClockFifo(Int16, 32)
    #core.outputs[1] = output
    input = core.fifos[1]

    # Run this test until 50 bytes of data has been recieved or until timeout.
    count = 0
    while count < 100 && length(readdata) < 50
        # Write data to the input fifo.
        payload_index = writeto!(input, payload, payload_index)
        runfor(core, 200)
     #   readfrom!(output, readdata)

        @show core.pc
        @show AsapSim.stall_fifo_check(core)
        @show input.num_reads

        count += 1
    end

    @show readdata

end
