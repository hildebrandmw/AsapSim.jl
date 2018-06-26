# Programs testing branch behavior.

# This function tests branching forward when predicting that the branch will
# be taken. (Note - branch is always taken)
#
# Expect dmem addresses 0 and 5 to be written to, but not 1, 2, 3, and 4
@asap4asm function branch_forward_taken_1()
    MOVI(dmem[0], 1)
    BRL(exit)
    MOVI(dmem[1], 2)
    MOVI(dmem[2], 3)
    MOVI(dmem[3], 4)
    MOVI(dmem[4], 5)
    @label exit
    MOVI(dmem[5], 10)
end

# This function tests branching forward when predicting that the branch will
# be NOT taken. (Note - branch is always taken)
#
# This will force the pipeline to deal with the branch mispredict penalty.
#
# Expect dmem addresses 0 and 5 to be written to, but not 1, 2, 3, and 4
@asap4asm function branch_forward_untaken_1()
    MOVI(dmem[0], 1)
    BR(exit)
    MOVI(dmem[1], 2)
    MOVI(dmem[2], 3)
    MOVI(dmem[3], 4)
    MOVI(dmem[4], 5)
    @label exit
    MOVI(dmem[5], 10)
end

# A couple degenerate cases with no trailing instructions
@asap4asm function branch_forward_taken_2()
    MOVI(dmem[0], 1)
    BR(exit)
    @label exit
    MOVI(dmem[1], 1)
end
# A couple degenerate cases with no trailing instructions
@asap4asm function branch_forward_untaken_2()
    MOVI(dmem[0], 1)
    BRL(exit)
    @label exit
    MOVI(dmem[1], 1)
end

# -- Branch Chain -- #
# Try mixing forward and backward branches together.
# All branches are still taken, thouch with a mix of predicted taken and
# predicted not-taken.
@asap4asm function branch_stress_1()
    # Should only set dmem entries 0 to 4.
    MOVI(dmem[0], 1)
    @label label1
        BR(label4)
        MOVI(dmem[50], 1)
        MOVI(dmem[51], 1)
        MOVI(dmem[52], 1)

    @label label2
        MOVI(dmem[3], 1)
        BRL(exit)
        MOVI(dmem[59], 1)
        MOVI(dmem[60], 1)
        MOVI(dmem[61], 1)

    @label label3
        MOVI(dmem[2], 1)    
        BR(label2)
        MOVI(dmem[56], 1)
        MOVI(dmem[57], 1)
        MOVI(dmem[58], 1)

    @label label4
        MOVI(dmem[1], 1)
        BRL(label3)
        MOVI(dmem[53], 1)
        MOVI(dmem[54], 1)
        MOVI(dmem[55], 1)

    @label exit
        MOVI(dmem[4], 1)

end


# --- Test using the Jump and Return feature --- #

# This should set the return_address register. This is just mainly a test to
# make sure that happens.
@asap4asm function test_jump_1()
    NOP()
    # The address of the branch instruction is address 2.
    #
    # Thus, the return address saved should be address 3.
    BR(exit, j)
    @label exit
    NOP()
    NOP()
    NOP()
    NOP()
end

# When branching from a RPT block, when the branch is at the end of the
# RPT, must make sure that the return address marks the BEGINNING of the RPT
# loop.
@asap4asm function test_jump_2()

    # Note, RPT is instruction 1, so the start of the RPT block is instruction
    # 2, which should be the return_address saved after the jump.
    RPT(10, nop3)
        NOP()
        NOP()
        BR(exit, j)
    END_RPT()
    # Some dummy move instructions that should be cleaned up by the 
    # misprediction handling logic
    MOVI(dmem[1], 1)
    MOVI(dmem[2], 1)
    MOVI(dmem[3], 1)
    @label exit
    MOVI(dmem[0], 1)
end

# Test returning from a Jump
@asap4asm function test_return_1()
    @label main
        BRL(test_label, j) 
        MOVI(dmem[1], 1, nop3)
        BRL(exit, nop2)

    @label test_label
        MOVI(dmem[0], 1)
        BRL(:return)
        MOVI(dmem[5], 1)
        MOVI(dmem[6], 1)
        MOVI(dmem[7], 1)

    @label exit
        MOVI(dmem[2], 1)
end
