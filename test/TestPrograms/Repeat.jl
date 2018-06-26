# Programs testing the RPT Instruction.

# Just sandwich an add between RPT instructions.
# If we repeat 10 times, final result should be 10
@asap4asm function repeat_1()
    RPT(10, nop3)
    ADD(dmem[0], 1, bypass[1])
    END_RPT()
end

# Try inserting 2 instructions between start of repeat and end of repeat.
# Use Bypass to to basically interleave these two instructions.
#
# Results in dmem[0] and dmem[1] should both be 10
@asap4asm function repeat_2()
    RPT(10, nop3)
    ADD(dmem[0], 1, bypass[2])
    ADD(dmem[1], 1, bypass[2])
    END_RPT()
end

# Try inserting 3 instructions. Use bypass register 3 to do the same trick
# that we did in repeat_2, but with 3 ADD instrucitons.
@asap4asm function repeat_3()
    RPT(10, nop3)
    ADD(dmem[0], 1, bypass[3])
    ADD(dmem[1], 1, bypass[3])
    ADD(dmem[2], 1, bypass[3])
    END_RPT()
end

# Use the RPT instruction to repeatedly call a function.
@asap4asm function repeat_4()
    # Move 1 into DMEM 0.
    #
    # Our silly little function is going to add this value to itself and then
    # return.
    MOVI(dmem[0], 1)
    RPT(10, nop3)
        BRL(add_dmem_0, j)
    END_RPT()
    BRL(exit)

    @label add_dmem_0
        ADD(dmem[0], 1, dmem[0], nop3)
        BRL(back)

    @label exit
        MOVI(dmem[1], 1)
end

# Jump out of one repeat loop into another repeat loop. Make sure that the
# other repeat loop gets initialized properly.
@asap4asm function repeat_5()
    RPT(5, nop3)
        BRL(second_loop)
    END_RPT()
    BRL(exit)

    @label second_loop
        MOVI(dmem[0], 0, nop3)
        RPT(10, nop3)
            ADD(dmem[0], 1, bypass[1])
        END_RPT()
        BRL(exit)

    @label exit
        MOVI(dmem[1], 10)
end

