#=
Implementation of the KC2 pipeline.
=#

# There's a lot of twiddling in dealing with some of the bitmasks for some
# instructions. This is a helpful function to avoid writing out a lot of this
# manually.
@inline isbitset(x::Integer, i) = (x & (1 << i)) != 0

# Basically clock the core.
function update!(core::AsapCore)

    # First, get a record of all the stall signals that are active this cycle.
    stalls = stall_check(core)
    # Look at Stage 4 to see if a misprediction happened. Must do this before
    # next PC is calculated.
    mispredict = checkbranch(core)

    # Evaluate stage 0 - get the next-state signals to avoid changing the
    # state of "core" until the end of the cycle.
    stage0_nextstate = pipeline_stage0(core, stalls.stall_01, mispredict)

    # Update pipe stages 1, 2, and 3.
    # These are mutating functions and will change their start-of-stage pipeline
    # entries.
    #
    # At the end, we will have to shift these entries in the pipeline according
    # to the set stall signals.
    if !stalls.stall_01
        stage1_next = pipeline_stage1(
            core, 
            stage0_nextstate.pc,
            stage0_nextstate.next_pc_unbranched,
        )
    end

    if !stalls.stall_234
        stage2_next = pipeline_stage2(
            core, 
            stalls.nop_2, 
            mispredict,
            stage0_nextstate.next_pc_unbranched,
        )

        stage3_next = pipeline_stage3(core, mispredict)

        # Stage 4 sets new ALU Flags. Since these flags are used in Stage 5 to
        # evaluate conditional execution, store them here and update the flags
        # at the end of this function.
        stage4_next, stage4_nextstate = pipeline_stage4(core, mispredict)
    end

    if !stalls.stall_5678

        # Evaluate Stages 5, 6, and 7. These again are mutating functiong with
        # no returned next state.
        stage5_next = pipeline_stage5(core, stalls.nop_5)
        stage6_next = pipeline_stage6(core)
        stage7_next = pipeline_stage7(core)

        # Do Stage 8 write-back. Note that this stage never stalls, but after it
        # executes, it turns its instruction into a NOP which avoids further
        # writebacks.
        pipeline_stage8(core)
    end

    # Stage 0 update
    core.pc             = stage0_nextstate.pc
    core.repeat_count   = stage0_nextstate.repeat_count
    core.repeat_start   = stage0_nextstate.repeat_start
    core.repeat_end     = stage0_nextstate.repeat_end
    core.return_address = stage0_nextstate.return_address


    # Shuffle the pipeline - start at the end and move forward.
    pipeline = core.pipeline
    if !stalls.stall_01
        pipeline.stage1 = stage1_next
    end

    if !stalls.stall_234
        pipeline.stage2 = stage2_next
        pipeline.stage3 = stage3_next
        pipeline.stage4 = stage4_next
        core.aluflags = stage4_nextstate
    end

    if !stalls.stall_5678
        pipeline.stage5 = stage5_next
        pipeline.stage6 = stage6_next
        pipeline.stage7 = stage7_next
    end

    # Clock the read side of the input fifos.
    for fifo in core.fifos
        readupdate!(fifo)
    end

    # Clock the write side of the output fifos.
    for fifo in values(core.outputs)
        writeupdate!(fifo)
    end

    return nothing
end


#-------------------------------------------------------------------------------
#                          Stage 0 - PC Control
#-------------------------------------------------------------------------------

# There's a circular dependency between the PC update and updates of various
# signals down the pipeline. We don't want this stage to mutate the state of
# the Core and for down-stream pipeline stages to see those changes until the
# next call to "update". So, have pipeline_stage0 return a struct with the
# next state for items in the core. This can then be updated later to mutate
# "core" without those changes being visible to other pipestages this cycle.
struct Stage0NextState 
    # Next state of the program counter.
    pc :: Int
    # Hardware looper
    repeat_count :: Int
    repeat_start :: Int
    repeat_end   :: Int
    # New return address
    return_address :: Int

    # Data that's not part of the state but needs to be passed to Stage 1 to
    # create new instructions linked to the correct return address
    next_pc_unbranched :: Int
end


# NOTE: Need to think about how to best structure this for testing.
function pipeline_stage0(core::AsapCore, stall::Bool, mispredict)
    # Initialize the next state values to the current state of the core.
    pc_next = core.pc
    repeat_count_next = core.repeat_count
    repeat_start_next = core.repeat_start
    repeat_end_next   = core.repeat_end
    return_address_next = core.return_address

    # Grab stage 4 to determine if a write is occuring to the return_address
    # register
    stage4 = core.pipeline.stage4

    ## Setup some preliminary variables to use elsewhere
    repeat_loop = core.pc == core.repeat_end && core.repeat_count > 1

    # Compute the next PC if no branch happens
    next_pc_unbranched = (!stall && repeat_loop) ? core.repeat_start : core.pc + 1

    # --------------------- #
    # Update repeat counter #
    # --------------------- #

    # If a past branch was mispredicted, restore the old repeat count because the
    # new one is potentially out-dated
    if mispredict
        repeat_count_next = core.pipeline.stage3.old_repeat_count

    # Check if stage 3 is a RPT instruction. If so, grab the value of the repeat
    # counter and store it.
    elseif core.pipeline.stage3.instruction.op == RPT
        repeat_count_next = Int(core.pipeline.stage3.src1_value)

    # Check if PC is equal to the current repeat end block and there are pending
    # repeats. If so, decrement the repeat counter.
    elseif !stall && repeat_loop
        repeat_count_next = core.repeat_count - 1
    end

    # ---------------------------------- #
    # Update repeat start and end blocks #
    # ---------------------------------- #
    if core.pipeline.stage3.instruction.op == RPT
        repeat_start_next = repeat_start(core.pipeline.stage3.instruction)
        repeat_end_next = repeat_end(core.pipeline.stage3.instruction)
    end

    # --------------------- #
    # Update return address #
    # --------------------- #

    # Four cases:
    # 1. Mispredicted jump - update to jump's next instruction
    # 2. Stage 5 write to return address
    # 3. Mispredicted non-jump. Restore the old return address.
    # 4. S1 has a new predicted taken branch.
    if mispredict && core.pipeline.stage3.instruction.jump
        return_address_next = core.pipeline.stage3.old_alternate_pc

    # If explicitly writing to return_address in Stage 5
    elseif stage4.instruction.dest == RET
        # TODO: Do a bounds check to make sure this stays in bounds.
        return_address_next = Int(stage4.result)

    # Check if rolling back a non-jump instruction
    elseif mispredict && !core.pipeline.stage3.instruction.jump
        return_address_next = core.pipeline.stage3.old_return_address

    # Check if stage 1 has a predicted-taken jump. If so, save the return
    # address as the next untaken PC.
    elseif !stall && core.pipeline.stage1.instruction.op == BRL && core.pipeline.stage1.instruction.jump
        return_address_next = next_pc_unbranched
    end

    # ---------------- #
    # Update PC Conter #
    # ---------------e #

    # Rollback from mispredicted branches
    if mispredict
        # If mispredicted branch was a return, go to its return address
        if core.pipeline.stage3.instruction.isreturn
            pc_next = core.pipeline.stage3.old_return_address

        # If this branch was auto-taken, restore to its PC + 1
        elseif core.pipeline.stage3.instruction.op == BRL
            pc_next = core.pipeline.stage3.old_alternate_pc

        # Otherwise, go to its target.
        else
            pc_next = Int(branch_target(core.pipeline.stage3.instruction))
        end

    # Do nothing if stalling this stage.
    elseif stall
        pc_next = core.pc

    # Check for autobranching for the instruction in stage 1.
    elseif core.pipeline.stage1.instruction.op == BRL
        if core.pipeline.stage1.instruction.isreturn
            pc_next = core.return_address
        else
            pc_next = Int(branch_target(core.pipeline.stage1.instruction))
        end
    else
        pc_next = next_pc_unbranched
    end

    # Return state updates to caller
    return Stage0NextState(
        pc_next,
        repeat_count_next,
        repeat_start_next,
        repeat_end_next,
        return_address_next,
        next_pc_unbranched,
    )
end

#-------------------------------------------------------------------------------
#                               Stage 1
#-------------------------------------------------------------------------------
@inline function pipeline_stage1(core::AsapCore, pc, next_pc)

    # TODO: Make this correct.
    if pc <= length(core.program)
        instruction = core.program[pc]
    else
        instruction = InstNOP()
    end
    # Insert this instruction into the pipeline.
    nextstage = PipelineEntry(instruction)

    return nextstage
end

#-------------------------------------------------------------------------------
#                               Stage 2
#-------------------------------------------------------------------------------
@inline function dereference(core::AsapCore, loc::Loc)
    operand = sym(loc)
    index   = ind(loc)
    # If the provided "operand" is accessing an address generater, hardware
    # pointer, or bypass pointer, replace the operand with ":dmem" and the
    # index with the value of the pointer. Otherwise, return `operand` and
    # `index` unchanged.

    # Check for "pointer" reference
    if operand == POINTER
        operand = DMEM
        # Add 1 to "index" to convert from 0-based indexing to 1-based indexing.
        index = Int(core.pointers[index + 1])

    # Check for address generator with no increment.
    elseif operand == AG
        operand = DMEM
        index = Int(read(core.address_generators[index + 1]))

    # Address generator with increment.
    #
    # This just marks the address generator as needing an increment. The actual
    # incremeting operation will happen after all operands in the instruction
    # have had a chance to be dereferenced.
    elseif operand == AG_PI
        # Mark this generator as needing an update.
        #
        # Do this before updating index - otherwise we're gonna have a bad
        # time ...
        mark(core.address_generators[index + 1])

        operand = DMEM
        index = Int(read(core.address_generators[index + 1]))

    elseif operand == POINTER_BYPASS
        operand = DMEM
        # Read from the result of Stage 5 (since pipe stages here are the
        # beginning of stage values, this is the computed result of the last
        # Stage 4)
        index = Int(core.pipeline.stage4.result)
    end

    # Return new operand and index. If the provided operand was not a
    # dereference, we just return them unchanded.
    return Loc(operand, index)
end

# TODO: Early kill for conditional check.
@inline function pipeline_stage2(
        core        :: AsapCore, 
        nop         :: Bool, 
        mispredict  :: Bool,
        pc_unbranched :: Integer,
    )

    if mispredict
        # Must clean out pending NOPs if mispredicted.
        core.pending_nops = 0
        return PipelineEntry()
    end

    # Grab the input from stage 1
    stage1 = core.pipeline.stage1
    instruction = stage1.instruction

    # Check if we're supposed to insert NOPs. If so, just do that and
    # return.
    if nop
        core.pending_nops -= 1
        nextstate = PipelineEntry()

    else
        # Do pointer dereference checks.
        # If any source or destination is targeting an address generator or hardware
        # pointer, get the DMEM address of that pointer and convert the instruction
        # into a DMEM instruction.

        # Do dereference checks for each operand of the instruction.
        dest = dereference(core, instruction.dest)
        src1 = dereference(core, instruction.src1)
        src2 = dereference(core, instruction.src2)

        # Update all of the address generators that have been read from this cycle.
        for ag in core.address_generators
            increment!(ag)
        end

        # Update the instruction in the pipeline.
        operands = SrcDestCollection(dest, src1, src2)
        new_instruction = set(instruction, operands)
        # Replace the instruction in the pipeline with possibly dereferenced version
        # of the instruction.
        nextstate = set(stage1, INSTRUCTION(new_instruction))

        # Check if the instruction was a branch. If so, record the unbranched
        # PC as well as repeat count and return address.
        if nextstate.instruction.optype == BRANCH_TYPE
            return_values = RETURNS(
                core.return_address,
                pc_unbranched,
                core.repeat_count,
            )
            nextstate = set(nextstate, return_values)
        end

        # Check if this instruction requests any NOPs.
        # If so, modify the the NOP counter.
        if instruction.nops > 0
            core.pending_nops = instruction.nops
        end
    end

    return nextstate
end

#-------------------------------------------------------------------------------
#                               Stage 3
#-------------------------------------------------------------------------------

function stage3_read(core::AsapCore, loc::Loc)
    operand = sym(loc)
    index   = ind(loc)
    # Default the return value to 0. If the operand doesn't perform a read
    # this stage, this is what will be returned.
    #
    # TODO: Think about changing this with a Union{Missing,Int16} when using
    # Julia 0.7+. May be a little more precise about if something has been
    # read or not.
    return_value::Int16 = 0

    # Do a check for immediates.
    if operand == IMMEDIATE
        # For immediates, the index in the instruction is the value of the
        # immediate. Note that this also takes core of extended immediates
        # because I'm treating that very loosely.
        return_value = signed(UInt16(unsigned(index) & 0xFFFF))

    # Check accumulator
    elseif operand == ACC
        # Take the lower 16-bits of the accumulator.
        return_value = signed(UInt16(core.accumulator & 0xFFFF))

    # Check bypass registers 3 and 5
    elseif operand == BYPASS
        if index == 3
            # Get the result from stage 6
            return_value = core.pipeline.stage5.result
        elseif index == 5
            # Get the result from stage 8
            return_value = core.pipeline.stage7.result
        end

    # Check if using the return address.
    elseif operand == RET
        return_value = core.return_address

    # DMEM read - while technically this is routed in Stage 4, we get the
    # correct behavior if we just do the read here.
    elseif operand == DMEM
        # Add 1 to index to convert from index 0 to index 1.
        return_value = core.dmem[index + 1]
    end

    return return_value
end

@inline function pipeline_stage3(core::AsapCore, mispredict)
    # Don't do anything if stalled - skip if instruction is a nop.
    stage2 = core.pipeline.stage2
    instruction = stage2.instruction

    instruction.op == NOP   && return PipelineEntry()

    if mispredict
        nextstate = PipelineEntry()
    else

        # Handle the reading of operands.
        src1_value = stage3_read(core, instruction.src1)
        src2_value = stage3_read(core, instruction.src2)

        nextstate = set(stage2, SRC(src1_value, src2_value))
    end

    return nextstate
end

#-------------------------------------------------------------------------------
#                               Stage 4
#-------------------------------------------------------------------------------
@inline function pipeline_stage4(core::AsapCore, mispredict)
    stage3 = core.pipeline.stage3
    instruction = stage3.instruction
    new_aluflags = core.aluflags

    instruction.op == NOP   && return PipelineEntry(), new_aluflags

    if mispredict
        return PipelineEntry(), new_aluflags
    end


    # Do a stage 4 read. Provide a default value for already read instructions.
    src1_value = stage4_read(core, instruction.src1, stage3.src1_value)
    src2_value = stage4_read(core, instruction.src2, stage3.src2_value)

    nextstate = set(stage3, SRC(src1_value, src2_value))

    # If this is an ALU operation ... do an ALU evaluation.
    if instruction.optype == ALU_TYPE
        result, new_aluflags = stage4_alu(
            instruction.op, 
            src1_value,
            src2_value,
            core.aluflags, 
            core.condexec
        )
        nextstate = set(nextstate, RESULT(result))
    end

    return nextstate, new_aluflags
end


function stage4_read(core::AsapCore, loc::Loc, default::U) where U
    operand = sym(loc)
    index   = ind(loc)

    # Default the return value
    return_value::U = default

    # Check if this is a fifo read.
    if operand == IBUF
        # TODO: Maybe check that the FIFO is indeed ready to be read here.
        # The stall check ... SHOULD ... take care of this, but if there are
        # bugs going on, it might be helpful.
        fifo = core.fifos[index + 1]
        return_value = read(fifo)

    # Read from FIFO without increment.
    elseif operand == IBUF_NEXT
        fifo = core.fifos[index + 1]
        return_value = peek(fifo)

    # TODO: Packet Routers and memory

    # Read from bypass registers 1, 2, and 4.
    elseif operand == BYPASS
        if index == 1
            return_value = core.pipeline.stage4.result
        elseif index == 2
            return_value = core.pipeline.stage5.result
        elseif index == 4
            return_value = core.pipeline.stage7.result
        end
    end

    return return_value
end

# Helper function.
function asap_add(x::Int32, y::Int32)
    # Julia default to 2's complement arithmetic, so this will return the 
    # correct result even if arguments are supposed to be unsigned.
    result_32 = x + y
    result = signed(UInt16(result_32 & 0xFFFF))
    cout = isbitset(result, 17)
    overflow = cout ⊻ isbitset(result, 16)

    return result, cout, overflow
end

function asap_add(::Type{Unsigned}, x::Int16, y::Int16, c::Bool = false)
    asap_add(Int32(unsigned(x)), Int32(unsigned(y)) + Int32(c))
end

function asap_add(::Type{Signed}, x::Int16, y::Int16, c::Bool = false)
    asap_add(Int32(x), Int32(y) + Int32(c))
end

function asap_sub(::Type{Unsigned}, x::Int16, y::Int16, c::Bool = false)
    asap_add(Int32(unsigned(x)), Int32(-y) - Int32(c))
end

function asap_sub(::Type{Signed}, x::Int16, y::Int16, c::Bool = false)
    asap_add(Int32(x), Int32(-y) - Int32(c))
end

#function asap_add(::Type{T}, x::Int16, y::Int16) where T
#    # Extend inputs to 32 bits - allows checking of bit 17 for carry out that
#    # correctly handles signed and unsigned cases.
#    
#    # Check carry out
#    cout = (typemax(UInt16) - unsigned(x)) < unsigned(y)
#    result = x + y
#    overflow = (x > 0 && y > 0 && result < 0) || (x < 0 && y < 0 && result > 0)
#    # Return sum and carry-out. Since all arithmetic in Julia is in 2's
#    # complement, we don't need to worry about converting "x" and "y" to
#    # unsigned because we'll get the same end result.
#    return x + y, cout, overflow
#end
#asap_add(x::Int16, y::Int16, cin::Int16) = asap_add(x, y + cin)

function stage4_alu(
        op :: AsapOpcode,
        src1,
        src2,
        flags::ALUFlags,
        cxflags::Vector{CondExec}
    )
    # Unpack the instruction from the pipeline stage to get the instruction
    # op code.
    #instruction = stage.instruction

    # # Get the instruction inputs.
    # src1 = stage.src1_value
    # src2 = stage.src2_value


    # Convert the carry flag and overflow flags to Int16s
    carry_next = flags.carry
    overflow_next = flags.overflow

    # # Begin a big long chain of IF-else cases.
    # op = instruction.op

    # Break instructions into two categories:
    #
    # Addition and subtraction logic, which will share carry detection and
    # saturation at the end, and other more complicated logic.
    result::Int16 = 0

    # Unsigned Addition
    if op == ADDSU || op == ADDU
        result, carry_next, overflow_next = asap_add(Unsigned, src1, src2)
    elseif op == ADDS || op == ADD
        result, carry_next, overflow_next = asap_add(Signed, src1, src2)
    elseif op == ADDCSU || op == ADDCU
        result, carry_next, overflow_next = asap_add(Unsigned, src1, src2, flags.carry)
    elseif op == ADDCS || op == ADDC
        result, carry_next, overflow_next = asap_add(Signed, src1, src2, flags.carry)

    # Unsigned subtraction
    elseif op == SUBSU || op == SUBU 
        result, carry_next, overflow_next = asap_sub(Unsigned, src1, src2)
    elseif op == SUBS || op == SUB
        result, carry_next, overflow_next = asap_sub(Signed, src1, src2)
    elseif op == SUBCSU || op == SUBCU
        result, carry_next, overflow_next = asap_sub(Unsigned, src1, src2, flags.carry)
    elseif op == SUBCS || op == SUBC
        result, carry_next, overflow_next = asap_sub(Signed, src1, src2, flags.carry)
    # Logic operations.
    elseif op == OR
        result = src1 | src2
    elseif op == AND
        result = src1 & src2
    elseif op == XOR
        result = src1 ⊻ src2

    # Move Ops
    elseif op == MOVE || op == MOVI
        result = src1
    elseif op == MOVC
        result = flags.carry ? src1 : src2
    elseif op == MOVZ
        result = flags.zero ? src1 : src2
    elseif op == MOVCX0
        result = cxflags[1].flag ? src1 : src2
    elseif op == MOVCX1
        result = cxflags[2].flag ? src2 : src2

    # Reduction operators.
    elseif op == ANDWORD
        result = (src1 == Int16(0xFFFF)) ? Int16(1) : Int16(0)
    elseif op == ORWORD
        result = (src1 == 0) ? Int16(0) : Int16(1)
    elseif op == XORWORD
        result = isodd(count_ones(src1)) ? Int16(1) : Int16(0)

    # Special operators
    elseif op == BTRV
        error("BTRV not implemented yet")
    elseif op == LSD
        result = (src1 < 0) ? count_ones(src1) - 1 : count_zeros(src1) - 1
    elseif op == LSDU
        result = count_zeros(src1)

    # Shift operations
    elseif op == SHL
        # Since we store numbers as signed, must check if src2 is negative.
        result = (src2 >= 16 || src2 < 0) ? 0 : Int(src1) << src2
        carry_next = (result & 0x10000) != 0
        result = Int16(result & 0xFFFF)
    elseif op == SHR
        # Shift left 1 so we can capture the carry bit.
        result = Int(unsigned(src1)) << 1
        result = (src2 > 16 || src2 < 0) ? 0 : result >> src2
        # Carry the low bit
        carry_next = (result & 1) != 0
        result = Int16((result >> 1) & 0xFFFF)
    elseif op == SRA
        result = Int(src1) << 1
        result = (src2 > 16 || src2 < 0) ? 0 : result >> src2
        carry_next = (result & 1) != 0
        result = Int16((result >> 1) & 0xFFFF)

    # Shift left and carry
    elseif op == SHLC
        # Insert carry on the right - preshift by 1
        result = Int(src1) << 1 | Int(flags.carry)
        result = (src2 >= 16 || src2 < 0) ? 0 : result << src2
        # Because of the pre-shift, the new carry is at bit 17
        carry_next = (result & 0x20000) != 0
        result = Int16((result >> 1) & 0xFFFF)

    elseif op == SHRC # Shift right and carry
        # Insert carry-in on the left.
        # Make room for carry out on the right by left-shifting by 1
        result = (Int(unsigned(src1)) | (Int(flags.carry) << 16)) << 1
        result = (src2 > 16 || src2 < 0) ? 0 : result >> src2
        carry_next = (result & 1) != 0
        result = Int16((result >> 1) & 0xFFFF)

    elseif op == SRAC
        result = (Int(src1) | Int(flags.carry) << 16) << 1
        result = (src2 > 16 || src2 < 0) ? 0 : result >> src2
        carry_next = (result & 1) != 0
        result = Int16((result >> 1) & 0xFFFF)

    # Unrecognized instruction
    else
        error("Unrecognized op $op.")
    end

    # Update the zero and negative flats.
    zero_next = result == 0
    negative_next = (result & 0x8000) != 0

    # Return the next carry flags.
    return result, ALUFlags(
        carry_next,
        negative_next,
        overflow_next,
        zero_next,
    )
end

"""
    checkbranch(core::AsapCore, stage)

Return `true` if branch instruction in `stage` was mispredicted. Return `true`
otherwise.
"""
function checkbranch(core::AsapCore)
    # Get stage 4 of the pipeline.
    stage = core.pipeline.stage3

    # If this is not a branch, exit early.
    stage.instruction.op == BR || stage.instruction.op == BRL || return false

    # Determine if this branch is predicted taken or not.
    #
    # Assume that the check for the branch instruction has happened before entry
    # into this function.
    predict_taken = (stage.instruction.op == BRL)

    # Get the branch mask from the instruction.
    aluflags = core.aluflags
    mask = stage.src1_value
    instruction = stage.instruction

    # The bit positions of the mask are as follows:
    # 12 - Negate results
    # 11 - Unconditional (always taken)
    # 10 - Full memory output (TODO)
    #  9 - Full packet output (TODO)
    #  8 - Any obuf direction full
    #  7 - Empty memory input (TODO)
    #  6 - Empty packet input (TODO)
    #  5 - Empty IBUF1
    #  4 - EmptyeIBUF0
    #  3 - Overflow
    #  2 - Carry
    #  1 - Zero
    #  0 - Negative

    # Do a BIT short-circuiting evaulation of everything.
    #
    # This is kind of messy - but not ... TOO .. bad ...
    branch_taken_preinversion =
        # Always bit check
        isbitset(mask, 11) ||
        # ALU Flags
        (isbitset(mask, 0) && aluflags.negative)   ||
        (isbitset(mask, 1) && aluflags.zero)       ||
        (isbitset(mask, 2) && aluflags.carry)      ||
        (isbitset(mask, 3) && aluflags.overflow)   ||
        (isbitset(mask, 4) && isempty(core.fifo[1])) || # NOTE: Converted to index 1
        (isbitset(mask, 5) && isempty(core.fifo[2])) ||
        (isbitset(mask, 8) && checkoutputs(core))

    # If the invert bit is set, do that to switch the branch evaluation.
    branch_taken = isbitset(mask, 12) ?
        ~branch_taken_preinversion :
        branch_taken_preinversion

    # Do a conditional execution check for this branch.
    #
    # If this branch fails the conditional execution check, it's not taken.
    if (instruction.cxflag == CX_TRUE && !core.condexec[instruction.cx_index + 1]) ||
        (instruction.cxflag == CX_FALSE && core.condexec[instruction.cx_index + 1])
        branch_taken = false
    end

    # Check if the branch was mispredicted.
    mispredicted = branch_taken ⊻ predict_taken
    return mispredicted
end


#-------------------------------------------------------------------------------
#                               Stage 5
#-------------------------------------------------------------------------------
@inline function pipeline_stage5(core::AsapCore, nop::Bool)
    # Skip if stalled or ALU. If given NOP, replace stage 5 with a NOP.
    stage4 = core.pipeline.stage4
    instruction = stage4.instruction

    instruction.op == NOP  && return PipelineEntry()

    # If indicated that this instruction should return a NOP - make it so.
    if nop
        return PipelineEntry()
    end

    # Okay, we're going ahead with normal execution. Do the stage-5 saturation
    # if requested.
    if instruction.saturate
        nothing
        #saturate!()
    end

    # Handle writeback to return address.
    # Done in Stage 0
    # if instruction.dest == :ret
    #     core.return_address = stage5.result
    # end

    # ----------------------------- #
    # --- Conditional Execution --- #
    # ----------------------------- #

    # Set flags
    if instruction.cxflag == CX_SET
        # Get the conditional execution unit to use.
        condexec = core.condexec[instruction.cxindex + 1]

        setflag!(condexec, core, stage4)

    # Check if this instruction has a conditional execution flag and if
    # it should continue or not.
    #
    # CXT : Pass if flag is set.
    elseif instruction.cxflag == CX_TRUE
        # If the flag is not set, make this instruction a NOP
        if !core.condexec[instruction.cxindex + 1].flag
            return PipelineEntry()
        end

    # CXF : Pass if flag is NOT set
    elseif instruction.cxflag == CX_FALSE
        # If the flag IS set, make this a NOP
        if core.condexec[instruction.cxindex + 1].flag
            return PipelineEntry()
        end
    end

    return stage4

end

function saturate!(stage::PipelineEntry, aluflags::ALUFlags)
    # Check if this instruction was signed.
    issigned = stage.instruction.signed

    if issigned
        # Check the carry and negative flags to determine how to saturate it.
        #
        # If you think about this really hard, it kind of makes sense.
        #
        # TODO: Think about this more to figure out if it REALLY makes sense
        # or not.
        if (aluflags.carry == false) && (aluflags.negative == true)
            stage.result = typemax(Int16)
        elseif (aluflags.carry == true) && (aluflags.negative == false)
            stage.result = typemin(Int16)
        end
    else
        if aluflags.carry == true
            stage.result = signed(typemax(UInt16))
        end
    end
    return nothing
end

function setflag!(condexec::CondExec, core::AsapCore, stage)
    # Create a bit-vector for the flags.
    #
    # Since there are 11 mask bits, set this to falses of lenght 11.
    flags = falses(11)
    mask = condexec.mask

    # The condexec mask bits are as follows:
    # 10 - Full memory output (TODO)
    #  9 - Full packet output (TODO)
    #  8 - Any OBUF Mask full
    #  7 - Empty memory input (TODO)
    #  6 - Empty packet input (TODO)
    #  5 - Empty ibuf 1
    #  4 - Empty ibuf 0
    #  3 - ALU Overflow
    #  2 - ALU Carry
    #  1 - ALU zero
    #  0 - ALU Negative.
    # Just kind of brute force check these things.

    # Check OBUF masks
    if isbitset(mask, 8)
        # Iterate through the selected outputs of the obuf_mask.
        #
        # If any output is full, set bit 8 of the flags to zero and move on.
        for (index, bit) in enumerate(core.obuf_mask)
            bit || continue
            if isfull(core.outputs[index])
                flags[8] = true
                break
            end
        end
    end

    # Check IBUFS
    if isbitset(mask, 5)
        flags[5] = isempty(core.fifo[2])
    end
    if isbitset(mask, 4)
        flags[4] = isempty(core.fifo[1])
    end

    # Check ALU Flags.
    aluflags = core.aluflags

    if isbitset(mask, 3)
        flags[3] = aluflags.overflow
    end
    if isbitset(mask, 2)
        flags[2] = aluflags.carry
    end
    if isbitset(mask, 1)
        flags[1] = aluflags.zero
    end
    if isbitset(mask, 0)
        flags[0] = flags.negative
    end

    # Perfrom the reduction and set the flag.
    if condexec.unary_op == :OR
        condexec.flag = reduce(|, flags)
    elseif condexec.unary_op == :AND
        condexec.flag = reduce(&, flags)
    else
        condexec.flag = reduce(⊻, flags)
    end
    return nothing
end


#-------------------------------------------------------------------------------
#                               Stage 6
#-------------------------------------------------------------------------------

# Dummy stage to simulate pipelined multiplier. Actual multiplication happens
# in stage 7.
pipeline_stage6(core::AsapCore) = core.pipeline.stage5


#-------------------------------------------------------------------------------
#                               Stage 7
#-------------------------------------------------------------------------------
multiply(::Type{Signed}, a, b) = Int(signed(a)) * Int(signed(b))
multiply(::Type{Unsigned}, a, b) = UInt(unsigned(a)) * UInt(unsigned(b))

low(x) = signed(UInt16(x & 0xFFFF))
high(x) = signed(UInt16((x >> 16) & 0xFFFF))

@inline function pipeline_stage7(core::AsapCore)
    # Get the start of pipe stage and instruction.
    stage6 = core.pipeline.stage6
    instruction = stage6.instruction

    # Don't do anything if stalled.
    instruction.op == NOP  && return PipelineEntry()

    # Multiply if the instruction is of the correct type.
    if instruction.optype == MAC_TYPE
        result, accumulator = stage4567_multiply(stage6, core.accumulator)

        # Set core acculator and store result.
        core.accumulator = accumulator
        nextstate = set(stage6, RESULT(result))
    else
        nextstate = PipelineEntry()
    end
    return nextstate
end

function stage4567_multiply(stage, accumulator)
    # Another long list of conditionals depending on OP type.

    instruction = stage.instruction
    op = instruction.op
    src1_value = stage.src1_value
    src2_value = stage.src2_value

    result::Int16 = 0
    # Signed Multiply - return low
    if op == MULTL
        result = low(multiply(Signed, src1_value, src2_value))
    # Unsigned multiply - return low
    elseif op == MULTLU
        result = low(multiply(Unsigned, src1_value, src2_value))
    # Signed multiply - return high
    elseif op == MULTH
        result = high(multiply(Signed, src1_value, src2_value))
    # Unsigned multiply - return high
    elseif op == MULTHU
        result = high(multiply(Unsigned, src1_value, src2_value))
    # Signed multiply accumulate. Return low bits of accumulator.
    elseif op == MACL
        # Since the accumulator is signed, just do normal arithmetic with it.
        accumulator += multiply(Signed, src1_value, src2_value)
        result = low(accumulator)
    # Unsigned multiply accumulate. Return low bits.
    elseif op == MACLU
        unsigned_result = multiply(Unsigned, src1_value, src2_value) + 
            unsigned(accumulator)

        accumulator = signed(unsigned_result)
        result = low(accumulator)
    # Signed multiply accumulate. Return high bits of accumulator.
    elseif op == MACH
        accumulator += multiply(Signed, src1_value, src2_value)
        result = high(accumulator)
    # Unsigned multiply accumulate. Return high bits.
    elseif op == MACHU
        unsigned_result = multiply(Unsigned, src1_value, src2_value) + 
            unsigned(accumulator)

        accumulator = signed(unsigned_result)
        result = high(accumulator)

    # Signed multiply accumulate, wipe accumulator. Return low.
    elseif op == MACCL
        accumulator = multiply(Signed, src1_value, src2_value)
        result = low(accumulator)

    # Unsigned multiply accumulate, wipe accumulator. Return low.
    elseif op == MACCLU
        core.accumulaor = signed(multiply(Unsigned, src1_value, src2_value))
        result = low(accumulator)

    # Signed multiply accumulate, wipe accumulator. Return high.
    elseif op == MACCH
        accumulator = multiply(Signed, src1_value, src2_value)
        result = high(accumulator)

    # Unsigned multiply accumulate, wipe accumulator. Return high.
    elseif op == MACCHU
        core.accumulaor = signed(multiply(Unsigned, src1_value, src2_value))
        result = high(accumulator)

    # --- Accumulator shifts
    # Pick one of 4 shift amounts depending on src1_value
    # 0: >> 1
    # 1: >> 8
    # 2: >> 16
    # 3: << 16
    # Always return low bits of accumulator.

    # Signed shift - preserve sign bits.
    elseif op == ACCSH
        if src1_value == 0
            accumulator >>= 1
        elseif src1_value == 1
            accumulator >>= 8
        elseif src1_value == 2
            accumulator >>= 16
        elseif src1_value == 3
            accumulator <<= 16
        end

    # Unsigned shift. Use the ">>>" operator.
    elseif op == ACCSHU
        if src1_value == 0
            accumulator >>>= 1
        elseif src1_value == 1
            accumulator >>>= 8
        elseif src1_value == 2
            accumulator >>>= 16
        elseif src1_value == 3
            accumulator <<= 16
        end
    else
        error("Unrecognized MAC op: $(op)")
    end

    # Truncate the accumulator to only use 4 bits. Do this by shifting left
    # then arithmetic shifting right to preserve signed bits.
    #
    # NOTE: The behavior of this might not quite be right is an unsigned 
    # instruction follows a signed instruction ... 
    accumulator = ((accumulator << 64 - 40) >> (64 - 40))

    return result, accumulator
end

#-------------------------------------------------------------------------------
#                               Stage 8
#-------------------------------------------------------------------------------

# Write back stage
@inline function pipeline_stage8(core::AsapCore)
    stage5 = core.pipeline.stage5
    stage7 = core.pipeline.stage7

    # Select stage 8 for write back if is is not a NOP, it's a MAC operation,
    # and it's destination is not ":null"
    if stage7.instruction.op != NOP &&
        sym(stage7.instruction.dest) != NULL &&
        stage7.instruction.optype == MAC_TYPE

        writeback!(core, stage7)

    elseif stage5.instruction.op != NOP &&
            sym(stage5.instruction.dest) != NULL &&
            stage5.instruction.optype != MAC_TYPE

        writeback!(core, stage5)
    end

    return nothing
end

# TODO: Fill this out more completely.
function writeback!(core::AsapCore, stage::PipelineEntry)
    # Unpack some common information
    instruction = stage.instruction
    dest        = sym(instruction.dest)
    index       = ind(instruction.dest)
    result      = stage.result

    # Writeback to DMEM
    if dest == DMEM
        # For now, only handle write to DMEM
        @assert stage.instruction.sw
        core.dmem[index + 1] = stage.result

    # Write to an output buffer
    elseif dest == OUTPUT
        write(core.outputs[index + 1], result)

    # Write to hardware pointers.
    elseif dest == SET_POINTER 
        # Write to the pointer in question.
        core.pointers[index + 1] = result

    # Configure AG Start and Stop
    elseif dest == AG_START
        # Get the start and stop values.
        start = unsigned(result & 0xFF)
        stop  = unsigned((result >> 8) & 0xFF)
        set!(core.address_generators[index + 1], start, stop)

    # Configure AG Stride
    elseif dest == AG_STRIDE
        set_stride!(core.address_generators[index + 1], result)

    # Set CX Mask
    elseif dest == CXMASK
        set!(core.condexec[index + 1], result)

    # Set OBUF Mask
    elseif dest == OBUF_MASK
        setobufmask!(core, result) 

    end


    return nothing
end
