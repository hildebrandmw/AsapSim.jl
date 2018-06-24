# Collection of programs to test source reads #

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

# Use MOVI -> bypass register 1 -> MACL to get a multiplication
# of two numbers. Capture bypass register 4 using another MOVE 
# instruction.
@asap4asm function bypass_4()
    MOVI(dmem[0], 100)
    MULTL(dmem[1], bypass[1], 10)
    NOP()
    NOP()
    NOP()
    ADD(dmem[2], bypass[4], bypass[4])
end

# This is like the bypass_4 test, but we have 1 more NOP between the
# multiply and the add.
@asap4asm function bypass_5()
    MOVI(dmem[0], 100)
    MULTL(dmem[1], bypass[1], 10)
    NOP()
    NOP()
    NOP()
    NOP()
    ADD(dmem[2], bypass[5], bypass[5])
end

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
