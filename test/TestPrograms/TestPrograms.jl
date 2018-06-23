# Collection of test programs to help with testing and debugging of the Simulator.
module TestPrograms
    # Wouldn't make much sense to have a collection of test programs if we 
    # didn't include the simulator module now would it?
    using AsapSim

    # ----------------------------- #
    # Test reading from all sources #
    # ----------------------------- #
    export test_core

    # Create a test-core with some fields initialized for easier testing.
    #
    # 
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

    # Programs to execute on the test core.

    # Move an immediate to dmem location 0
    @asap4asm function move_immediate()
        MOVI(dmem[0], 100)
    end

    # Read the return address.
    @asap4asm function move_return_address()
        MOVE(dmem[0], ret)
    end

    # Read from accumulator
    @asap4asm function move_accumulator()
        MOVE(dmem[0], acc)
    end

    # -- Bypass registers -- #
    @asap4asm function bypass_1()
        MOVI(null, 10)
        MOVE(dmem[0], bypass[1])
    end

    @asap4asm function bypass_2()
        MOVI(null, 10)
        NOP()
        MOVE(dmem[0], bypass[2])
    end

    @asap4asm function bypass_3()
        MOVI(null, 10)
        NOP()
        NOP()
        MOVE(dmem[0], bypass[3])
    end

    # TODO: Implement the multiplier so I can test these.
    # @asap4asm function bypass_4()
    # end

    # @asap4asm function bypass_5()
    # end

    # -- Pointer Dereferences -- #
    @asap4asm function pointers()
        MOVE(dmem[0], pointer[0])
        MOVE(dmem[1], pointer[1])
        MOVE(dmem[2], pointer[2])
        MOVE(dmem[3], pointer[3])
    end

    # -- Address Generator
    @asap4asm function address_generators()
        # Just dereference the address generator without incrementing.
        MOVE(dmem[0], ag[0])
        # Now dereference it, but increment.
        MOVE(dmem[1], ag_pi[0])
        # Dereference and add, but this time use an ADD instruction to make
        # sure that the address generator is not incremented twice.
        ADD(dmem[2], ag_pi[0], ag_pi[0]) 
        # Make sure the increment worked.
        MOVE(dmem[3], ag[0])
    end

    # -- Pointer bypass -- #
    @asap4asm function pointer_bypass()
        # Want to dereference memory 12
        MOVI(null, 12)
        NOP()
        NOP()
        # Dereference by bypass pointer and store the result to memory 0.
        #
        # Expect the result to be 10.
        MOVE(dmem[0], pointer_bypass)
    end

    # -- Fifo reads -- #
    # TODO: When writeback to outputs gets implemented, make sure stages 5, 6,
    # and 7 don't stall if one of them is writing to an output.
    @asap4asm function fifo_read()
        # This instruction should stall before writeback.
        MOVI(dmem[0], 10)
        # Read ibuf and increment
        MOVE(dmem[1], ibuf[0])
        # Read again, but don't increment
        MOVE(dmem[2], ibuf_next[0])
        MOVE(dmem[3], ibuf[0])
    end

end
