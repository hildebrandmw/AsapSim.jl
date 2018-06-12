# Condition and ALU flags for conditional execution, etc.
#
# Make this a struct with an API to possibly reimplement as a single integer
# with bit-twiddling instead of a struct of Bools. Probably not needed but
# may save some space in the future.
mutable struct ALUFlags
    carry       :: Bool
    negative    :: Bool
    overflow    :: Bool
    zero        :: Bool
end
ALUFlags() = ALUFlags(false, false, false, false)

mutable struct AddressGenerator
    start       ::Int16
    stop        ::Int16
    current     ::Int16
    stride      ::Int16
end
AddressGenerator() = AddressGenerator(0,0,0,0)

mutable struct CondExec
    flag        :: Bool
    mask        :: Int16,
    unary_op    :: Int16
    early_kill  :: Bool
end
CondExec() = CondExec(false, 0, 0, false)

# For keeping track of instructions through the pipeline.
# Essentially just a wrapper for the instruction with an extra slot for the
# result.
@with_kw mutable struct PipelineEntry
    instruction :: AsapInstruction
    # The actual source and result values
    src1_value  :: Int16 = 0
    src2_value  :: Int16 = 0
    result      :: Int16 = 0

    # Data for rolling-back branches. This doesn't really need to be recorded
    # at every stage, but it will be cleaner to do it this way. It doesn't take
    # that much memory anyways.
    old_return_address :: Int64 = 0 
    old_pc_plus_1      :: Int64 = 0
    old_repeat_count   :: Int64 = 0
end

PipelineEntry(i::AsapInstruction = NOP()) = PipelineEntry(instruction = i)
function PipelineEntry(core::AsapCore, inst::AsapInstruction = NOP())
    return PipelineEntry(
        instruction = inst,
        old_return_address  = core.return_address
        old_pc_plus_1       = core.pc + 1
        old_repeat_count    = core.repeat_count
    )
end

# Only record the states in stages 3-8. Stages 1-2 are decode stages so there's
# not much interesting to record there.
mutable struct AsapPipeline
    stage1 :: PipelineEntry
    stage2 :: PipelineEntry
    stage3 :: PipelineEntry
    stage4 :: PipelineEntry
    stage5 :: PipelineEntry
    stage6 :: PipelineEntry
    stage7 :: PipelineEntry
    stage8 :: PipelineEntry
end

# Initialize to an empty pipeline.
AsapPipeline() = AsapPipeline(
    PipelineEntry(),
    PipelineEntry(),
    PipelineEntry(),
    PipelineEntry(),
    PipelineEntry(),
    PipelineEntry(),
    PipelineEntry(),
    PipelineEntry(),
)


@with_kw mutable struct AsapCore
    # --- Timing Control --- #

    # Clock period - for registering updates.
    clock_period :: Int64

    # --- Program --- #

    # Stored program and program counter.
    program ::Vector{AsapInstruction} = AsapInstruction[]
    repeat_count        :: Int64 = 0
    repeat_block_start  :: Int64 = 0
    repeat_block_end    :: Int64 = 0
    pc      ::Int64 = 1

    # Mispredicted branch - done in S4
    branch_mispredict :: Bool = false

    # --- Misc storage elements --- #

    # Input fifo - default the element types of the fifo to Int16s.
    fifos::Vector{DualClockFifo{Int16}} = [
        DualClockFifo(Int16, 32),
        DualClockFifo(Int16, 32),
    ]

    # Address generators.
    address_generators::Vector{AddressGenerator} = [
        AddressGenerator(),
        AddressGenerator(),
        AddressGenerator(),
    ]

    # Hardware pointers
    pointers :: Vector{Int16} = zeros(Int16, 4)

    # Flags
    alu_flags :: ALUFlags = ALUFlags()

    # Conditional execution blocks
    cond_exec :: Vector{CondExec} = [
        CondExec(),
        CondExec(),
    ]

    # Data memory - again, default element types to Int16
    dmem::Vector{Int16} = zeros(Int16, 256)

    # Hardware return address buffer.
    return_address :: Int16 = 0

    # Number of pending NOPs to inser in stage 3 of the pipeline.
    # This is set by the options in the assembler.
    pending_nops :: Int16 = 0

    # --- Pipeline Bypass Registers --- #
    result_s5 :: Int16 = zero(Int16)
    result_s6 :: Int16 = zero(Int16)
    result_s8 :: Int16 = zero(Int16)

    # --- Pipeline --- #
    pipeline::AsapPipeline = AsapPipeline()
end

################################################################################
# Update Logic
################################################################################

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
function pipeline_stage1(core::AsapCore, stall_1::Bool)
    # Read instruction from pipestage.
    # TODO: Think about branching - repeat.
    # TODO: Stalling
    if !stall_1
        instruction = core.program[core.pc]
        core.pc += 1

        # Insert this instruction into the pipeline.
        core.pipeline.stage1 = PipelineEntry(instruction, 0)
    end
end

#-------------------------------------------------------------------------------
#                               Stage 2
#-------------------------------------------------------------------------------


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
