# Collection of test programs to help with testing and debugging of the Simulator.
module TestPrograms
    # Wouldn't make much sense to have a collection of test programs if we 
    # didn't include the simulator module now would it?
    using AsapSim

    # Simple function to do some arithmetic on immediates and dmem.
    #
    # Should cover a range of ALU functions, writes/reads to/from dmem, and 
    # usage of bypass registers.
    #
    # Don't have any branches - save those for a separate branch test function.
    @asap4asm function simple_arithmetic()
        # Move two immediate values into dmem locations 0 and 1
        MOVI(dmem[0], 10, csx0)
        MOVI(dmem[1], 20)
    end
end
