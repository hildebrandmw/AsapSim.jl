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
    # Run the core some more. The MOVI instruction should write back, but the
    # read from the IBUF should be stalled.
    runfor(core, 4)
    @test core.dmem[1] == 10
    @test core.dmem[2] == 0
    # Write again to the fifo.
    write(fifo, fifo_value_2)
    AsapSim.writeupdate!(fifo)
    runfor(core, 10)

    @test core.dmem[2] == fifo_value_1
    @test core.dmem[3] == fifo_value_2
    @test core.dmem[4] == fifo_value_2
end

@testset "Running Repeat Test" begin
    core = test_core(TestPrograms.repeat_1())
    runfor(core, 20)
    @test core.dmem[1] == 10

    core = test_core(TestPrograms.repeat_2())
    runfor(core, 40)
    @test core.dmem[1] == 10
    @test core.dmem[2] == 10

    core = test_core(TestPrograms.repeat_3())
    runfor(core, 60)
    @test core.dmem[1] == 10
    @test core.dmem[2] == 10
    @test core.dmem[3] == 10
end
