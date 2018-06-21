#=
Implementation of the KC2 pipeline.
=#

#-------------------------------------------------------------------------------
#                          Stage 0 - PC Control
#-------------------------------------------------------------------------------

# NOTE: Need to think about how to best structure this for testing.
function pipeline_stage0(core::AsapCore, stall::Bool)
    # Grab info from stage 1 - need to look at instructions as they come out
    # of the IMEM to detect branches.
    stage1 = core.pipeline.stage1

    # Grab stage 4 from the pipeline.
    # This will indicate:
    # - If a branch was mispredicted
    # - The direction that branch was taken
    # - PC and repeat counter state before the branch was executed
    # - Branch instruction flags: Jump and Return
    stage4 = core.pipeline.stage4

    # Grab stage 5 to determine if a write is occuring to the return_address
    # register
    stage5 = core.pipeline.stage5

    ## Setup some preliminary variables to use elsewhere
    repeat_loop = core.pc == core.repeat_block_end && core.repeat_count > 1

    # Compute the next PC if no branch happens
    next_pc_unbranched = (!stall && repeat_loop) ? core.repeat_block_start : core.pc + 1


    # --------------------- #
    # Update repeat counter #
    # --------------------- #

    # If a past branch was mispredicted, restore the old repeat count because the
    # new one is potentially out-dated
    if core.branch_mispredict
        core.repeat_count = stage4.old_repeat_count
        
    # Check if stage 4 is a RPT instruction. If so, grab the value of the repeat
    # counter and store it.
    elseif stage4.instruction.op == :RPT
        core.repeat_count = stage4.src1_val

    # Check if PC is equal to the current repeat end block and there are pending
    # repeats. If so, decrement the repeat counter.
    elseif !stall && repeat_loop
        core.repeat_count -= 1
    end

    # ---------------------------------- #
    # Update repeat start and end blocks #
    # ---------------------------------- #
    if stage4.instruction.op == :RPT
        # TODO
        core.repeat_block_start
        core.repeat_block_end
    end

    # --------------------- #
    # Update return address #
    # --------------------- #

    # Four cases:
    # 1. Mispredicted jump - update to jump's next instruction
    # 2. Stage 5 write to return address
    # 3. Mispredicted non-jump. Restore the old return address.
    # 4. S1 has a new predicted taken branch.
    # TODO
    if core.branch_mispredict && stage4.instruction.options.jump
        core.return_address = stage4.old_pc_plus_1

    # If explicitly writing to return_address in Stage 5
    elseif stage5.instruction.dest == :return_address
        # TODO: Do a bounds check to make sure this stays in bounds.
        core.return_address = stage5.result

    # Check if rolling back a non-jhump instruction
    elseif core.branch_mispredic && !stage4.instruction.options.jump
        core.return_address = stage4.old_return_address

    # Check if stage 1 has a predicted-taken jump. If so, save the return
    # address as the next untaken PC.
    elseif !stall && stage1.instruction.op == :BRL && stage1.instruction.options.jump
        core.return_address = next_pc_unbranched
    end
    
    # ---------------- #
    # Update PC Conter #
    # ---------------- #

    # Rollback from mispredicted branches
    if core.branch_mispredict
        # If mispredicted branch was a return, go to its return address
        if stage4.instruction.src1 == :return_address
            core.pc = stage4.old_return_address

        # If this branch was auto-taken, restore to its PC + 1
        elseif stage4.instruction.op == :BRL
            core.pc = stage4.old_pc_plus_1

        # Otherwise, go to its target.
        else
            core.pc = branch_target(stage4.instruction)
        end

    # Do nothing if stalling this stage.
    elseif stall
        nothing

    # Check for autobranching for the instruction in stage 1.
    elseif stage1.instruction.op == :BRL
        if stage1.instruction.src1 == :return_address
            core.pc = core.return_address
        else
            core.pc = branch_target(stage1.instruction)
        end
    else
        core.pc = next_pc_unbranched
    end
end

#-------------------------------------------------------------------------------
#                               Stage 1
#-------------------------------------------------------------------------------
function pipeline_stage1(core::AsapCore, stall::Bool)
    # Read instruction from pipestage.
    if !stall
        instruction = core.program[core.pc]
        # Insert this instruction into the pipeline.
        core.pipeline.stage1 = PipelineEntry(core, instruction)
    end
end

#-------------------------------------------------------------------------------
#                               Stage 2
#-------------------------------------------------------------------------------
function pipeline_stage2(core::AsapCore, stall::Bool)
    # Don't do anything if stalled.
    stall && return nothing

    # Do pointer dereference checks.
    # If any source or destination is targeting an address generator or hardware
    # pointer, get the DMEM address of that pointer and convert the instruction
    # into a DMEM instruction.
    stage2 = core.pipeline.stage2
    instruction = stage2.instruction

end



#-------------------------------------------------------------------------------
#                               Stage 3
#-------------------------------------------------------------------------------

function pipeline_stage3(core::AsapCore, stall::Bool)
    # Don't do anything if stalled. 
    stall && return nothing
end

#-------------------------------------------------------------------------------
#                               Stage 4
#-------------------------------------------------------------------------------

# Helper function.
# Convert all of the arguments to unsigned numbers, perform the operation,
# then convert back to signed.
#
# Due to the magic of inlining, this all seems to get opimized away. Hooray!
#op_unsigned(op, args...) = Int64(op(reinterpret.(UInt16, args)...))

function asap_add(x::Int16, y::Int16)
    # Check carry out 
    cout = (typemax(UInt16) - reinterpret(UInt16, x)) < reinterpret(UInt16, y)
    result = x + y
    overflow = (x > 0 && y > 0 && result < 0) || (x < 0 && y < 0 && result > 0)
    # Return sum and carry-out. Since all arithmetic in Julia is in 2's 
    # complement, we don't need to worry about converting "x" and "y" to 
    # unsigned because we'll get the same end result.
    return x + y, cout, overflow
end
asap_add(x::Int16, y::Int16, cin::Bool) = asap_add(x, y + Int16(cin))

function stage_4_alu(
        stage::PipelineEntry, 
        flags::ALUFlags, 
        cxflags::Vector{CondExec}
    )
    # Unpack the instruction from the pipeline stage to get the instruction
    # op code.
    instruction = stage.instruction

    # Get the instruction inputs.
    src1 = stage.src1_value
    src2 = stage.src2_value


    # Convert the carry flag and overflow flags to Int16s
    carry_next = flags.carry
    overflow_next = flags.overflow

    # Begin a big long chain of IF-else cases.
    op = instruction.op

    # Break instructions into two categories:
    #
    # Addition and subtraction logic, which will share carry detection and 
    # saturation at the end, and other more complicated logic.

    if instruction.addsub

        overflow_next = false
        # Unsigned Addition
        if op == :ADDSU || op == :ADDU || op == :ADDS || op == :ADD
            stage.result, carry_next, overflow_next = asap_add(src1, src2)
        elseif op == :ADDCSU || op == :ADDCU || op == :ADDCS || op == :ADDC
            stage.result, carry_next, overflow_next = asap_add(src1, src2, flags.carry)

        # Unsigned subtraction
        elseif op == :SUBSU || op == :SUBU || op == :SUBS || op == :SUB
            stage.result, carry_next, overflow_next = asap_add(src1, -src2)
        elseif op == :SUBCSU || op == :SUBCU || op == :SUBCS || op == :SUBC
            stage.result, carry_next, overflow_next = asap_add(src1, -src2, !flags.carry)

        else
            error("""
            Unrecognized addition-subtraction instruction: $op.
            """)
        end
        # Overflow is XOR or bits 15 and 16
        #overflow_next = (carry_next ⊻ ((stage.result & 0x8000) != 0))
    else
        # Logic operations.
        if op == :OR
            stage.result = src1 | src2
        elseif op == :AND
            stage.result = src1 & src2
        elseif op == :XOR
            stage.result = src1 ⊻ src2

        # Move Ops
        elseif op == :MOVE || op == :MOVI
            stage.result = src1
        elseif op == :MOVC
            stage.result = flags.carry ? src1 : src2
        elseif op == :MOVZ
            stage.result = flags.zero ? src1 : src2
        elseif op == :MOVCX0
            stage.result = cxflags[1].flag ? src1 : src2
        elseif op == :MOVCX1
            stage.result = cxflags[2].flag ? src2 : src2

        # Reduction operators.
        elseif op == :ANDWORD
            stage.result = (src1 == Int16(0xFFFF)) ? Int16(1) : Int16(0)
        elseif op == :ORWORD
            stage.result = (src1 == 0) ? Int16(0) : Int16(1)
        elseif op == :XORWORD
            stage.result = isodd(count_ones(src1)) ? Int16(1) : Int16(0)

        # Special operators
        elseif op == :BTRV
            error("BTRV not implemented yet")
        elseif op == :LSD
            stage.result = (src1 < 0) ? count_ones(src1) - 1 : count_zeros(src1) - 1
        elseif op == :LSDU
            stage.result = count_zeros(src1)

        # Shift operations
        elseif op == :SHL
            # Since we store numbers as signed, must check if src2 is negative.
            result = (src2 >= 16 || src2 < 0) ? 0 : Int(src1) << src2
            carry_next = (result & 0x10000) != 0
            stage.result = Int16(result & 0xFFFF)
        elseif op == :SHR
            # Shift left 1 so we can capture the carry bit.
            result = Int(reinterpret(UInt16, src1)) << 1
            result = (src2 > 16 || src2 < 0) ? 0 : result >> src2
            # Carry the low bit
            carry_next = (result & 1) != 0
            stage.result = Int16((result >> 1) & 0xFFFF)
        elseif op == :SRA
            result = Int(src1) << 1
            result = (src2 > 16 || src2 < 0) ? 0 : result >> src2
            carry_next = (result & 1) != 0
            stage.result = Int16((result >> 1) & 0xFFFF)

        # Shift left and carry
        elseif op == :SHLC
            # Insert carry on the right - preshift by 1
            result = Int(src1) << 1 | Int(flags.carry)
            result = (src2 >= 16 || src2 < 0) ? 0 : result << src2
            # Because of the pre-shift, the new carry is at bit 17
            carry_next = (result & 0x20000) != 0
            stage.result = Int16((result >> 1) & 0xFFFF)

        elseif op == :SHRC # Shift right and carry
            # Insert carry-in on the left.
            # Make room for carry out on the right by left-shifting by 1 
            result = (Int(reinterpret(UInt16, src1)) | (Int(flags.carry) << 16)) << 1
            result = (src2 > 16 || src2 < 0) ? 0 : result >> src2
            carry_next = (result & 1) != 0
            stage.result = Int16((result >> 1) & 0xFFFF)

        elseif op == :SRAC
            result = (Int(src1) | Int(flags.carry) << 16) << 1
            result = (src2 > 16 || src2 < 0) ? 0 : result >> src2
            carry_next = (result & 1) != 0
            stage.result = Int16((result >> 1) & 0xFFFF)

        # Unrecognized instruction
        else
            error("Unrecognized op $op.")
        end
    end

    # Update the zero and negative flats.
    zero_next = stage.result == 0
    negative_next = (stage.result & 0x8000) != 0

    # Return the next carry flags.
    return ALUFlags(
        carry_next,
        negative_next,
        overflow_next,
        zero_next,
    ) 
end


#-------------------------------------------------------------------------------
#                               Stage 5
#-------------------------------------------------------------------------------


#-------------------------------------------------------------------------------
#                               Stage 6
#-------------------------------------------------------------------------------


#-------------------------------------------------------------------------------
#                               Stage 7
#-------------------------------------------------------------------------------


#-------------------------------------------------------------------------------
#                               Stage 8
#-------------------------------------------------------------------------------
