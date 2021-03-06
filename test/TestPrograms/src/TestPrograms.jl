# Collection of test programs to help with testing and debugging of the Simulator.
module TestPrograms
    # Wouldn't make much sense to have a collection of test programs if we 
    # didn't include the simulator module now would it?
    using AsapSim

    export test_core, testfifo_core, runfor, writeto!, readfrom!

    #  --- Test reading from all sources  --- #
    include("Sources.jl")
    # --- Test writing to all destinations --- #
    include("Destinations.jl")
    # --- Test branch behavior --- #
    include("Branch.jl")
    # --- Test RPT Instruction --- #
    include("Repeat.jl")
    # --- Test Conditional Execution --- #
    #include("CondExec.jl") (TODO)

    # Simple programs
    include("Simple.jl")
    include("Sort.jl")
    include("Temp.jl")

    ####################
    # Helper Functions #
    ####################
    function runfor(core, cycles)
        for _ in 1:cycles
            AsapSim.update!(core)
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
            # Read from the fifo and mark it for incrementing.
            AsapSim.increment!(fifo)
            readupdate!(fifo)
        end
    end



    # Create a test-core with some fields initialized for easier testing.
    const RETURN_ADDRESS = 10
    # Set the accumulator to all 1's. Make sure we only grab the lower
    # 16 bits.
    const ACCUMULATOR    = 2^40 - 1

    # Initial DMEM contents
    # Address (index 1) => value
    const DMEM = Dict(
        128 + 1 => 128,
        129 + 1 => 129,
        130 + 1 => 130,
        131 + 1 => 131,

        # Initialize some values for the address generator test.
        12 + 1 => 10,
        14 + 1 => 20,
        16 + 1 => 30
    )

    function test_core(program)
        core = AsapCore(;
            # Initialize return address to test reading from it.
            return_address = RETURN_ADDRESS,
            accumulator = ACCUMULATOR,

            # Initialize pointers to DMEM addresses. Will initialize DMEM
            # addresses to verify these were dereferenced correctly.
            pointers = [128, 129, 130, 131],
        )

        # Initialize DMEM.
        for (k,v) in DMEM
            core.dmem[k] = v
        end

        # Set address generator 1 (0)
        core.address_generators[1] = AsapSim.AddressGenerator(
            start   = 10,
            stop    = 30,
            current = 12,
            stride  = 2,
        )

        # Attach the function to the core.
        core.program = program

        return core
    end

    function testfifo_core(program)
        core = AsapCore(;
            program = program,
            fifos = [AsapSim.TestFifo{Int16}(),AsapSim.TestFifo{Int16}()],
            outputs = AsapSim.SmallAssociative{Int,AsapSim.TestFifo{Int16}}(),
            #outputs = Dict{Int,AsapSim.TestFifo{Int16}}(),
        )


        return core
    end
end
