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
