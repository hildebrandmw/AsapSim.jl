function runfor(core, cycles)
    for _ in 1:cycles
        AsapSim.update!(core)
    end
end

@testset "Running Source Tests" begin

    
    # ------------------------- #
    # --- Run source tests  --- #
    # ------------------------- #

    # --- Move immediate --- #
    core = test_core(TestPrograms.move_immediate())
    # Clock core.
    runfor(core, 10)
    # Test that the immediate was moved into the final dmem location.
    # Note that we must convert to index 1 when accessing the dmem array in Core.
    @test core.dmem[1] == 100

    # --- Move Return Address --- #
    core = test_core(TestPrograms.move_return_address())
    runfor(core, 10)
    @test core.dmem[1] == TestPrograms.RETURN_ADDRESS

    # --- Move Accumulator --- #
    core =  test_core(TestPrograms.move_accumulator())
    runfor(core, 10)
    # Awkward conversion - take lower 16 bits of accumulator, convert to UInt16,
    # then reinterpret memory as Int16 to match the data types in DMEM.
    @test core.dmem[1] == reinterpret(Int16, UInt16(TestPrograms.ACCUMULATOR & 0xFFFF))

    # -- Bypass Registers -- #
    bypass_programs = (
        TestPrograms.bypass_1(), 
        TestPrograms.bypass_2(), 
        TestPrograms.bypass_3(),
    )
    for (index, program) in enumerate(bypass_programs)
        println("Testing Bypass Register: $index")
        core = test_core(program)
        runfor(core, 10)
        @test core.dmem[1] == 10
    end

    # Bypass 4
    println("Testing Bypass Register: 4")
    core = test_core(TestPrograms.bypass_4())
    runfor(core, 15)
    @test core.dmem[1] == 100
    @test core.dmem[2] == 100 * 10
    @test core.dmem[3] == 2 * 100 * 10

    # Bypass 5
    println("Testing Bypass Register: 5")
    core = test_core(TestPrograms.bypass_5())
    runfor(core, 15)
    @test core.dmem[1] == 100
    @test core.dmem[2] == 100 * 10
    @test core.dmem[3] == 2 * 100 * 10

    # -- Test pointer dereference -- #
    core = test_core(TestPrograms.pointers())
    runfor(core, 12)
    @test core.dmem[1] == TestPrograms.DMEM[128 + 1]
    @test core.dmem[2] == TestPrograms.DMEM[129 + 1]
    @test core.dmem[3] == TestPrograms.DMEM[130 + 1]
    @test core.dmem[4] == TestPrograms.DMEM[131 + 1]

    # -- Address Generator --
    core = test_core(TestPrograms.address_generators())
    runfor(core, 15)
    # Expect this to be the contents of DMEM at address 12 + 1.
    @test core.dmem[0 + 1] == TestPrograms.DMEM[12 + 1]
    # Since the address gneerator was not incremented, still expect it to have
    # dereferenced the same memory location.
    @test core.dmem[1 + 1] == TestPrograms.DMEM[12 + 1]
    # The previous instruction incremented the address generator. Since we used
    # an ADD instruction, we expect the result to be twice the value in memory
    # at address 14 + 1
    @test core.dmem[2 + 1] == 2 * TestPrograms.DMEM[14 + 1]
    # Since the ADD incremented the address generator, expect the result to be
    # the contents at DMEM 16 + 1
    @test core.dmem[3 + 1] == TestPrograms.DMEM[16 + 1]

    # -- Test Pointer Bypass -- #
    core = test_core(TestPrograms.pointer_bypass())
    runfor(core, 10)
    @test core.dmem[1] == TestPrograms.DMEM[12 + 1]


    # -- Run a fifo test -- #
    core = test_core(TestPrograms.fifo_read())
    runfor(core, 10)
    # Nothing should have been written back to memory, core should be stalled
    # on FIFO read.
    @test core.dmem[1] == 0

    fifo_value_1 = -1
    fifo_value_2 = -2
    # Write to the fifo.
    fifo = core.fifos[1]
    write(fifo, fifo_value_1)
    AsapSim.writeupdate!(fifo)
    # Run the core some more. The MOVI instruction should be stalled in stage 5
    # before wite back
    runfor(core, 4)
    @test core.dmem[1] == 0
    @test core.dmem[2] == 0
    # Write again to the fifo.
    write(fifo, fifo_value_2)
    AsapSim.writeupdate!(fifo)
    runfor(core, 10)

    @test core.dmem[1] == 10
    @test core.dmem[2] == fifo_value_1
    @test core.dmem[3] == fifo_value_2
    @test core.dmem[4] == fifo_value_2
end

################################################################################
# Branch Tests
################################################################################
@testset "Running Branch Tests" begin
    # Test branch predicted taken
    core = test_core(TestPrograms.branch_forward_taken_1())
    runfor(core, 20)
    # Make sure first MOVE worked
    @test core.dmem[1] == 1
    # These instructions should have been skipped.
    @test core.dmem[2] == 0
    @test core.dmem[3] == 0
    @test core.dmem[4] == 0
    @test core.dmem[5] == 0
    # This instruction should have been branced to and executed
    @test core.dmem[6] == 10

    # --
    core = test_core(TestPrograms.branch_forward_taken_2())
    runfor(core, 15)
    @test core.dmem[1] == 1
    @test core.dmem[2] == 1

    # -- Test branch predicted not-taken
    core = test_core(TestPrograms.branch_forward_untaken_1())
    runfor(core, 20)
    # Make sure first MOVE worked
    @test core.dmem[1] == 1
    # These instructions should have been skipped.
    @test core.dmem[2] == 0
    @test core.dmem[3] == 0
    @test core.dmem[4] == 0
    @test core.dmem[5] == 0
    # This instruction should have been branced to and executed
    @test core.dmem[6] == 10

    # --
    core = test_core(TestPrograms.branch_forward_untaken_2())
    runfor(core, 15)
    @test core.dmem[1] == 1
    @test core.dmem[2] == 1

    # ------------------ #
    # Branch Stress Test #
    # ------------------ #
    core = test_core(TestPrograms.branch_stress_1())
    runfor(core, 30)
    # Make sure the entries we want set are set
    for i in 1:5
        @test core.dmem[i] == 1
    end
    # Make sure nothing else was set.
    for i in 50:62
        @test core.dmem[i] == 0
    end

    # -------------------- #
    # Test Jump and Return #
    # -------------------- #
    core = test_core(TestPrograms.test_jump_1())
    runfor(core, 10)
    @test core.return_address == 3

    # Test that return address is handled correctly when called at the end
    # of a RPT block
    core = test_core(TestPrograms.test_jump_2())
    runfor(core, 20)

    # Make sure the return address was saved correctly
    @test core.return_address == 2
    @test core.dmem[1] == 1
    for i in 2:4
        @test core.dmem[i] == 0
    end

    # -- Test the retun instruction
    core = test_core(TestPrograms.test_return_1())
    runfor(core, 30)

    # Expect address 2 to be saved as the return address
    @test core.return_address == 2
    # Should have written 1 to addresses 0 - 2
    for i in 0:2
        @test core.dmem[i+1] == 1
    end
    # Should NOT have written to address 5 - 7
    for i in 5:7
        @test core.dmem[i+1] == 0
    end

end

@testset "Running Repeat Tests" begin
    core = test_core(TestPrograms.repeat_1())
    runfor(core, 20)
    @test core.dmem[1] == 10

    core = test_core(TestPrograms.repeat_2())
    runfor(core, 40)
    @test core.dmem[1] == 10
    @test core.dmem[2] == 10

    core = test_core(TestPrograms.repeat_3())
    @time runfor(core, 60)
    @test core.dmem[1] == 10
    @test core.dmem[2] == 10
    @test core.dmem[3] == 10

    # Test doing a function call.
    core = test_core(TestPrograms.repeat_4())
    @time runfor(core, 80)
    # Should have added 1 to dmem[0] 10 times. Since it should have started at
    # 1, the final value should be 11.
    @test core.dmem[1] == 11
    @test core.dmem[2] == 1

    # Test multiple repeat blocks.
    core = test_core(TestPrograms.repeat_5())
    @time runfor(core, 80)
    @test core.dmem[1] == 10
    @test core.dmem[2] == 10
end

################################################################################
# Destination Write Tests
################################################################################

@testset "Testing Destination Writes" begin
    # Test writing to hardware pointers.
    core = test_core(TestPrograms.pointer_write_1())
    runfor(core, 10)
    @test core.pointers[1] == 1
    @test core.pointers[2] == 2
    @test core.pointers[3] == 3
    @test core.pointers[4] == 4

    # Test writing to address generators
    core = test_core(TestPrograms.address_generator_write_1())
    runfor(core, 20)
    # AG 0
    @test core.address_generators[1].start == 10
    @test core.address_generators[1].stop == 20
    @test core.address_generators[1].stride == 3
    # AG 1
    @test core.address_generators[2].start == 0
    @test core.address_generators[2].stop == 255
    @test core.address_generators[2].stride == 255
    # AG 2
    @test core.address_generators[3].start == 100
    @test core.address_generators[3].stop == 0
    @test core.address_generators[3].stride == 1

    # Write to CX Mask
    core = test_core(TestPrograms.cxmask_write_1())
    runfor(core, 10)
    @test core.condexec[1].mask == signed(UInt16(0xFFFF))
    @test core.condexec[1].unary_op == :XOR
    @test core.condexec[1].early_kill == true

    # Test obuf mask write
    core = test_core(TestPrograms.obufmask_write_1())
    runfor(core, 10)
    for i in core.obuf_mask
        @test i == true
    end
end
