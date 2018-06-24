# Collection of test programs to help with testing and debugging of the Simulator.
module TestPrograms
    # Wouldn't make much sense to have a collection of test programs if we 
    # didn't include the simulator module now would it?
    using AsapSim

    export test_core

    #  --- Test reading from all sources  --- #
    include("Sources.jl")
    # --- Test writing to all destinations --- #
    #include("Destinations.jl") (TODO)
    # --- Test branch behavior --- #
    #include("Branch.jl") (TODO)
    # --- Test RPT Instruction --- #
    include("Repeat.jl")
    # --- Test Conditional Execution --- #
    #include("CondExec.jl") (TODO)



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
            pointers = [128, 129, 130, 131]
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
end
