#=
Implementation of the KC2 pipeline.
=#

# Basically clock the core.
function update!(core::AsapCore)

    # First, get a record of all the stall signals that are active this cycle.
    stalls = stall_check(core)
end


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
function dereference(core::AsapCore, operand::Symbol, index::T) where T
    # If the provided "operand" is accessing an address generater, hardware
    # pointer, or bypass pointer, replace the operand with ":dmem" and the
    # index with the value of the pointer. Otherwise, return `operand` and
    # `index` unchanged.

    # Check for "pointer" reference
    if operand == :pointer
        operand = :dmem
        # Add 1 to "index" to convert from 0-based indexing to 1-based indexing.
        index = T(core.pointers[index + 1])

    # Check for address generator with no increment.
    elseif operand == :ag
        operand = :dmem
        index = T(read(core.address_generators[index + 1]))

    # Address generator with increment.
    #
    # This just marks the address generator as needing an increment. The actual
    # incremeting operation will happen after all operands in the instruction 
    # have had a chance to be dereferenced.
    elseif operand == :ag_pi
        operand = :dmem
        index = T(read(core.address_generators[index + 1]))
        # Mark this generator as needing an update.
        masrk(core.address_generators[index + 1])

    elseif operand == :pointer_bypass
        operand = :dmem
        # Read from the result of Stage 5 (since pipe stages here are the 
        # beginning of stage values, this is the computed result of the last
        # Stage 4)
        index = T(core.pipeline.stage5.result)
    end

    # Return new operand and index. If the provided operand was not a 
    # dereference, we just return them unchanded.
    return (operand, index)
end

# TODO: Do NOP insertion
# TODO: Early kill for conditional check.
function pipeline_stage2(core::AsapCore, stall::Bool)
    # Don't do anything if stalled.
    stall && return nothing

    # Do pointer dereference checks.
    # If any source or destination is targeting an address generator or hardware
    # pointer, get the DMEM address of that pointer and convert the instruction
    # into a DMEM instruction.
    stage2 = core.pipeline.stage2
    instruction = stage2.instruction

    # Do dereference checks for each operand of the instruction.
    src1, src1_index = dereference(core, instruction.src1, instruction.src1_index)
    src2, src2_index = dereference(core, instruction.src2, instruction.src2_index)
    dest, dest_index = dereference(core, instruction.dest, instruction.dest_index)

    # Update all of the address generators that have been read from this cycle.
    for ag in core.address_generators
        increment!(ag)
    end

    # Update the instruction in the pipeline.
    operands = SrcDestCollection(src1, src1_index, src2, src2_index, dest, dest_index)
    new_instruction = reconstruct(instruction, operands)
    # Replace the instruction in the pipeline with possibly dereferenced version
    # of the instruction.
    core.pipeline.stage2.instruction = new_instruction

    return nothing
end

#-------------------------------------------------------------------------------
#                               Stage 3
#-------------------------------------------------------------------------------

function stage3_read(core::AsapCore, operand::Symbol, index::T) where T
    # Default the return value to 0. If the operand doesn't perform a read
    # this stage, this is what will be returned.
    #
    # TODO: Think about changing this with a Union{Missing,Int16} when using
    # Julia 0.7+. May be a little more precise about if something has been
    # read or not.
    return_value::Int16 = 0

    # Do a check for immediates.
    if operand == :immediate
        # For immediates, the index in the instruction is the value of the 
        # immediate. Note that this also takes core of extended immediates
        # because I'm treating that very loosely.
        return_value = Int16(index)

    # Check accumulator
    elseif operand == :acc
        # Take the lower 16-bits of the accumulator.
        return_value = reinterpret(Int16, core.accumulator & 0xFFFF)

    # Check bypass registers 3 and 5
    elseif operand == :bypass
        if index == 3
            # Get the result from stage 6
            return_value = core.pipeline.stage6.result
        elseif index == 5
            # Get the result from stage 8
            return_value = core.pipeline.srage8.result
        end

    # Check if using the return address.
    elseif operand == :ret
        return_value = core.return_address

    # DMEM read - while technically this is routed in Stage 4, we get the 
    # correct behavior if we just do the read here.
    elseif operand == :dmem
        # Add 1 to index to convert from index 0 to index 1.
        return_value = core.dmem[index + 1]
    end

    return return_value
end

function pipeline_stage3(core::AsapCore, stall::Bool)
    # Don't do anything if stalled - skip if instruction is a nop.
    stage3 = core.pipeline.stage3
    instruction = stage3.instruction

    (stall || instruction.op == :NOP) && return nothing

    # Handle the reading of operands. 
    stage3.src1_value = stage3_read(core, instruction.src1, instruction.src1_index)
    stage3.src2_value = stage3_read(core, instruction.src2, instruction.src2_index)

    return nothing
end

#-------------------------------------------------------------------------------
#                               Stage 4
#-------------------------------------------------------------------------------
function pipeline_stage4(core::AsapCore, stall::Bool)
    # Skip stalls and nops.
    stage4 = core.pipeline.stage4
    instruction = stage4.instruction

    (stall || instruction.op == :NOP) && return nothing

    # Do a stage 4 read. Provide a default value for alread-read instructions.
    stage4.src1_value = stage4_read(
        core,
        instruction.src1,
        instruction.src1_index,
        stage4.src1_value,
    )

    stage4.src2_value = stage4_read(
        core,
        instruction.src2,
        instruction.src2_index,
        stage4.src2_value,
    )

    # If this is an ALU operation ... do an ALU evaluation.
    if instruction.alu_op
        new_aluflags = stage4_alu(stage4, core.aluflags, core.condexec)

    # Do a check for the RPT instruction.
    elseif instruction.op == :RPT
        core.repeat_count = stage.src1_value
        # Start and end encoded in the instruction itself. Access these with
        # the accessor functions.
        core.repeat_start = repeat_start(instruction)
        core.repeat_end = repeat_end(instruction)
    end
end


function stage4_read(core::AsapCore, operand::Symbol, index::T, default::U) where {T,U}
    # Default the return value 
    return_value::U = default

    # Check if this is a fifo read.
    if operand == :ibuf
        # TODO: Maybe check that the FIFO is indeed ready to be read here.
        # The stall check ... SHOULD ... take care of this, but if there are
        # bugs going on, it might be helpful.
        fifo = core.fifo[index + 1]
        return_value = read(fifo)
        # Send a read request to increment the fifo
        read_request(fifo)

    # Read from FIFO without increment.
    elseif operand == :ibuf_next
        fifo = core.fifo[index + 1]
        return_value = read(fifo)

    # TODO: Packet Routers and memory

    # Read from bypass registers 1, 2, and 4.
    elseif operand == :bypass
        if index == 1
            return_value = core.stage5.result
        elseif index == 2
            return_value = core.stage6.result
        elseif index == 4
            return_value == core.stage8.result
        end
    end

    return return_value
end

# Helper function.
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

function stage4_alu(
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

"""
    checkbranch(core::AsapCore, stage)

Return `true` if branch instruction in `stage` was mispredicted. Return `true`
otherwise.
"""
function checkbranch(core::AsapCore, stage)
    # Determine if this branch is predicted taken or not.     
    #
    # Assume that the check for the branch instruction has happened before entry
    # into this function.
    predict_taken = (stage.instruction.op == :BRL)

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
    #  4 - Empty IBUF0
    #  3 - Overflow
    #  2 - Carry
    #  1 - Zero
    #  0 - Negative

    # Do a BIT short-circuiting evaulation of everything.
    #
    # This is kind of messy - but not ... TOO .. bad ...
    branch_taken_preinversion = 
        # Always bit check
        (mask & (1 << 11) != 0) ||
        # ALU Flags
        ((mask & (1 << 0) != 0) && aluflags.negative)   ||
        ((mask & (1 << 1) != 0) && aluflags.zero)       ||
        ((mask & (1 << 2) != 0) && aluflags.carry)      ||
        ((mask & (1 << 3) != 0) && aluflags.overflow)   ||
        ((mask & (1 << 4) != 0) && isempty(core.fifo[0])) ||
        ((mask & (1 << 5) != 0) && isempty(core.fifo[1])) ||
        ((mask & (1 << 8) != 0) && checkoutputs(core))

    # If the invert bit is set, do that to switch the branch evaluation.
    branch_taken = isbitset(mask, 12) ? 
        ~branch_taken_preinversion : 
        branch_taken_preinversion

    # Do a conditional execution check for this branch.
    #
    # If this branch fails the conditional execution check, it's not taken.
    if (instruction.cxt && !core.condexec[instruction.cx_index + 1]) ||
        (instruction.cxf && core.condexec[instruction.cx_index + 1])
        branch_taken = false
    end

    # Check if the branch was mispredicted.
    mispredicted = branch_taken ⊻ predict_taken
    return mispredicted
end

isbitset(x::Integer, i) = (x & (1 << i)) != 0

"""
    checkoutputs(core::AsapCore)

Return `true` if any of the output buffers selected by `core`'s obuf_mask is
full. Otherwise, return `false`.
"""
function checkoutputs(core::AsapCore)
    for (index, bit) in enumerate(core.obuf_mask)
        bit || continue
        if isfull(core.outputs[index])
            return true
        end
    end
    return false
end

#-------------------------------------------------------------------------------
#                               Stage 5
#-------------------------------------------------------------------------------
function pipeline_stage5(core::AsapCore, stall::Bool, nop::Bool)
    # Skip if stalled or ALU. If given NOP, replace stage 5 with a NOP.
    stage5 = core.pipelin3.stage5 
    instruction = stage5.instruction
    (stall || instruction.op == :NOP) && return nothing

    # If indicated that this instruction should return a NOP - make it so.
    if nop
        stage5.instruction = NOP()
        return nothing
    end

    # Okay, we're going ahead with normal execution. Do the stage-5 saturation
    # if requested.
    if instruction.saturate
        saturate!()
    end

    # Handle writeback to return address.
    if instruction.dest == :ret
        core.return_address = stage5.result
    end

    # ----------------------------- #
    # --- Conditional Execution --- #
    # ----------------------------- #

    # Set flags
    if instruction.csx
        # Get the conditional execution unit to use.
        condexec = core.condexec[instruction.cx_index + 1]

        setflag!(condexec, core, stage5)

    # Check if this instruction has a conditional execution flag and if 
    # it should continue or not.
    #
    # CXT : Pass if flag is set.
    elseif instruction.cxt
        # If the flag is not set, make this instruction a NOP
        if !core.condexec[instruction.cx_index + 1].flag
            stage5.instruction = NOP()
        end

    # CXF : Pass if flag is NOT set
    elseif instruction.cxf
        # If the flag IS set, make this a NOP
        if core.condexec[instruction.cx_index + 1].flag
            stage5.instruction = NOP()
        end
    end

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
            stage.result = reinterpret(Int16, typemax(UInt16))
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
    if mask & (1 << 8) != 0
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
    if mask & (1 << 5) != 0
        flags[5] = isempty(core.fifo[2])
    end
    if mask & (1 << 4) != 0
        flags[4] = isempty(core.fifo[1])
    end

    # Check ALU Flags.
    aluflags = core.aluflags

    if mask & (1 << 3) != 0
        flags[3] = aluflags.overflow
    end
    if mask & (1 << 2) != 0
        flags[2] = aluflags.carry
    end
    if mask & (1 << 1) != 0
        flags[1] = aluflags.zero
    end
    if mask & (1 << 0) != 0
        flags[0] = alufalgs.negative
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
pipeline_stage6(core::AsapCore, stall) = nothing


#-------------------------------------------------------------------------------
#                               Stage 7
#-------------------------------------------------------------------------------

# TODO: Implement the MAC operations.
pipeline_stage7(core::AsapCore, stall) = nothing


#-------------------------------------------------------------------------------
#                               Stage 8
#-------------------------------------------------------------------------------

# Write back stage
function pipeline_stage8(core::AsapCore, stall)
    stage6 = core.pipeline.stage6
    stage8 = core.pipeline.stage8

    # Select stage 8 for write back if is is not a NOP, it's a MAC operation,
    # and it's destination is not ":null"
    if stage8.instruction.op != :NOP && 
        stage8.instruction.dest != :null &&
        stage8.instruction.ismac

        writeback!(core, stage8)

    elseif stage6.instruction.op != :NOP &&
            stage6.instruction.dest != :null &&
            !stage6.instruction.ismac

        writeback!(core, stage6)

    end
end

# TODO: Fill this out more completely.
function writeback!(core::AsapCore, stage::PipelineEntry)
    # For now, only handle write to DMEM
    @assert stage.instruction.dest == :dmem
    @assert stage.instruction.sw

    address = stage.instruction.dest_index
    core.dmem[address + 1] = stage.result

    # Make this instruction a NOP to avoid multiple write-backs
    stage.instruction = NOP()

    return nothing
end
