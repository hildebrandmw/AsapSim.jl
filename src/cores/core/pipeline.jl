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
end



#-------------------------------------------------------------------------------
#                               Stage 3
#-------------------------------------------------------------------------------

function pipeline_stage3(core::AsapCore)
    # Check if any pending NOPS exist. If so, insert a NOP into the pipeline.
    if core.pending_nops > 0
        core.pipeline.stage3 = PipelineEntry()
    else
        # Fetch an instruction from the program. Increment the program counter.
        instruction = core.program[core.pc]
        core.pc += 1
        # Save this instruction as the new pipeline entry. Default the return
        # value to zero. This may cause complications instead of leaving it as
        # some for of unitialilzed, but will do for now.
        core.pipeline.stage3 = PipelineEntry(instruction, 0)
    end
end

#-------------------------------------------------------------------------------
#                               Stage 4
#-------------------------------------------------------------------------------


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
