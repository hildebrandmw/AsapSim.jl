# Test suite for DualClockFifo
@testset "Testing Dual Clock Fifo" begin
    # Instantiate a small fifo for easier testing. Everything should be 
    # parameterized to scale to larger fifos and fifos with different elements.
    buffersize = 3
    fifo = AsapSim.DualClockFifo(Int64, buffersize)

    @test AsapSim.buffersize(fifo) == buffersize
    @test AsapSim.isreadempty(fifo) == true

    # Do some testing of the "isfull" function, which is independent of the 
    # actual fifo implementation.
    @test AsapSim.isfull(1, 1, 3) == false
    @test AsapSim.isfull(2, 1, 3) == false
    @test AsapSim.isfull(3, 1, 3) == true
    @test AsapSim.isfull(3, 2, 3) == false
    @test AsapSim.isfull(1, 2, 3) == true
    @test AsapSim.isfull(2, 3, 3) == true

    # Verify that we can write to the fifo. Should be able to write two times
    # before receiving an invalid write signal.
    @test AsapSim.iswriteready(fifo) == true
    AsapSim.write(fifo, 10)
    AsapSim.writeupdate!(fifo)

    @test AsapSim.iswriteready(fifo) == true
    AsapSim.write(fifo, 20)
    AsapSim.writeupdate!(fifo)

    @test AsapSim.iswriteready(fifo) == false

    # ----------------- #
    # Test some reading #
    # ----------------- #
    # No read should be ready because we haven't requested a read yet.
    @test AsapSim.isreadready(fifo) == false
    AsapSim.increment!(fifo)
    AsapSim.readupdate!(fifo)

    @test AsapSim.isreadready(fifo) == true
    @test AsapSim.read(fifo) == 10

    # Set another read request before the next update.
    AsapSim.increment!(fifo)
    AsapSim.readupdate!(fifo)
    @test AsapSim.isreadready(fifo) == true
    @test AsapSim.read(fifo) == 20
    @test AsapSim.isreadempty(fifo) == true

    # Ensure we can keep reading from the fifo until we ask it to increment again.
    AsapSim.readupdate!(fifo)
    @test AsapSim.isreadready(fifo) == true
    AsapSim.increment!(fifo)
    AsapSim.readupdate!(fifo)
    @test AsapSim.isreadready(fifo) == false

    # Do another write
    AsapSim.write(fifo, 30)
    AsapSim.writeupdate!(fifo)
    AsapSim.readupdate!(fifo)
    @test AsapSim.isreadready(fifo) == true
    @test AsapSim.read(fifo) == 30
end

@testset "Running Long Fifo Test" begin

    # The goal here is to simulate two different clocks writing to the fifo over
    # a long period of time. 
    #
    # We will sweep through different "frequencies" for the read and write side,
    # writing random numbers and reading. A circular dequeue from DataStrucutres
    # will be used to ensure that data is being maintained correctly.
    #
    # 5 different cases will be tried:
    #
    # - write side much faster than read side
    # - write side slightly faster than read side
    # - both sides equal
    # - write side slightly slower than read side
    # - write side much slower than read side.

    write_periods = (1, 9, 10, 11, 20)
    read_periods  = (10, 10, 10, 10, 10)

    # Set up some parameters to allow variable testing if desired.
    buffersize = 32
    datatype = Int

    # Use the CircularDeque as a golden reference.
    que = DataStructures.CircularDeque{datatype}(buffersize)
    fifo = AsapSim.DualClockFifo(datatype, buffersize)

    # Number of "clock cycles" to run each test for.
    test_cycles = 10_000

    # Initialize random number generator seed for reproducibility
    srand(0)
    for (wp, rp) in zip(write_periods, read_periods)
        for i in 1:test_cycles
            # Do a read if possible and if we're on the correct cycle.
            if mod(i, rp) == 0
                if AsapSim.isreadready(fifo)
                    AsapSim.increment!(fifo)
                    readdata = AsapSim.read(fifo)
                    # Check that it matches the data from the que
                    @test readdata == shift!(que)
                end
                # clock the fifo
                AsapSim.readupdate!(fifo)
            end

            # Write if possible and on the correct cycle
            if mod(i, wp) == 0
                if AsapSim.iswriteready(fifo) 
                    writedata = rand(datatype)
                    push!(que, writedata)
                    AsapSim.write(fifo, writedata)
                end
                AsapSim.writeupdate!(fifo)
            end
        end
    end
end
