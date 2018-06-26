#=
Support same input format as asap2 sorting:
	- 2 records per core
	- Sort high to low: pass low keys.
	- Record is 5 words key, 45 word payload
	- 0x2A followed by 0 is the flush signal, which arrives between records.
	-- Treat any non-0 as flush.
	-- Post-flush value is the number of records to pass; 0 for the first core,
	   but will generally be >0 within the chain.
	-- The final core will supress the flush and count signals, and just transmits
	   output records.
	- 0 is the non-flush signal, indicates a new record to process.
AG layout:
	- AG0 points to low record key's low word, 5 words, stride backwards.
	- AG1 points to low record, 50 words, stride forward.
	- AG2 points to high record, 50 words, stride forward.
Storage:
	- 0: 1 if this is the first core in the chain, read single input.
	- 1: 1 if this is the last core in the chain, send to single output, dont pass count.
Set signed vs. unsigned key to configurable.
=#

function initialize_snakesort(core)
    # Initialize address generators
    AsapSim.set_stride!(core.address_generators[1], 0xFF)
    AsapSim.set_stride!(core.address_generators[2], 1)
    AsapSim.set_stride!(core.address_generators[3], 1)

    # Initialize CXMASK0
    AsapSim.set!(core.condexec[1], 1 << 2) 
end


#Function(Snakesort)
@asap4asm function snakesort(firstcore, lastcore, lastcore_flush)
    new_key_4 = Loc(:dmem, 1)
    new_key_3 = Loc(:dmem, 2)
    new_key_2 = Loc(:dmem, 3)
    new_key_1 = Loc(:dmem, 4)
    new_key_0 = Loc(:dmem, 5)
    num_records_to_pass = Loc(:dmem, 8)

    # Record 0 stored between 20 and 69
    # Key is 5 word range starting from low word of key and going backward.
    # So 24 down to 20.
    ag_config_full_record_0 = ((69 << 8) + 20)
    ag_config_key_0         = ((20 << 8 + 24))
    local_key_0_4 = Loc(:dmem, 20)
    local_key_0_3 = Loc(:dmem, 21)
    local_key_0_2 = Loc(:dmem, 22)
    local_key_0_1 = Loc(:dmem, 23)
    local_key_0_0 = Loc(:dmem, 24)

    # Record 1 stored between 70 and 119
    ag_config_full_record_1 = ((119 << 8) + 70)
    ag_config_key_1         = ((70 << 8) + 74)
    local_key_1_4 = Loc(:dmem, 70)
    local_key_1_3 = Loc(:dmem, 71)
    local_key_1_2 = Loc(:dmem, 72)
    local_key_1_1 = Loc(:dmem, 73)
    local_key_1_0 = Loc(:dmem, 74)

    low_key_ptr_pi  = :ag0pi
    low_key_ptr     = :ag0
    low_key_ptr_cfg = Loc(:ag_start, 0)

    low_record_ptr_pi  = :ag1pi
    low_record_ptr     = :ag1
    low_record_ptr_cfg = Loc(:ag_start, 1)

    high_record_ptr_pi  = :ag2pi
    high_record_ptr     = :ag
    high_record_ptr_cfg = Loc(:ag_start, 2)

    # Begin main loop.

    # Start a new record batch, after reset.
    @label start
	    # Peek at ibuf, check if the end of block code (any non-0) is found,
	    #  and go to flush code if so.
        MOVE(null, ibuf0)
        BR(flush_0_local_record_with_count, z, neg)
        # Otherwise not flushing

	    # Reuse the storage to low function.  Cycle low pointer between
	    #  memory blocks.
	    MOVI(low_record_ptr_cfg, ag_config_full_record_0)
	    # Set high to the same location; this is used if a flush signal is
	    #  seen before storing another record.
	    MOVI(high_record_ptr_cfg, ag_config_full_record_0, nop3) #TODO: nop2 this
	    # Load an initial record.
	    BRL(store_new_record_at_low, j)

	    # Read ibuf, check if the end of block code (any non-0) is found,
	    #  and go to flush code if so.
        MOVE(null, ibuf0)
	    BR(flush_1_local_record_with_count, z, neg)

	    # Otherwise not flushing, so load a second record.
	    # Set low pointer to next block.
	    MOVI(low_record_ptr_cfg, ag_config_full_record_1, nop3)
	    BRL(store_new_record_at_low, j)

	    # Find which record is lower to set proper pointers.
	    # This function jumps to get_new_key when done.
	    BRL(compare_local_records)

    @label get_new_key
	    # Peek at ibuf, check if the end of block code is found.
	    # 0 means not end of block; non-zero is end of block.
	    # Pass the control word to the next core either way.
	    # Last core will not write out if not passing flush signals.
	    if(lastcore == 1 && lastcore_flush == 0)
            MOVE(null, ibuf0)
	    else
            MOVE(output[0], ibuf0)
        end
	    BR(flush_2_local_record, z, neg)


	    # Get the next key.
        MOVE(new_key_4, ibuf0)
	    MOVE(new_key_3, ibuf0)
	    MOVE(new_key_2, ibuf0)
	    MOVE(new_key_1, ibuf0)
	    MOVE(new_key_0, ibuf0)

	    # Compare to the lowest local key.
	    # TODO: fast compare of high words and jump if new key is less, maybe.
        SUBU(null, low_key_ptr_pi, bypass[1])
        SUBCU(null, low_key_ptr_pi, bypass[3])
        SUBCU(null, low_key_ptr_pi, new_key_2)
        SUBCU(null, low_key_ptr_pi, new_key_3)
	    #if(Unsigned0_Signed1){
	    SUBC(null, low_key_ptr_pi, new_key_4, cxs) #Set if carry if true.
	    #}else{
	  #  	SUBCU(null, low_key_ptr_pi, new_key_4, cxs) #Set if carry if true.
	    #}
	    # If carry, new key is higher.

	    # If new key lower or equal, pass it with record to output.
	    # This function jumps to get_new_key when done.
	    BRL(pass_input_to_output, n, c)

	    # If new key higher, send the local low record to output.
	    # Store the new key and record at the previous low location.
	    # Key.
        MOVE(output[0], low_record_ptr)
	    MOVE(low_record_ptr_pi, new_key_4)
        MOVE(output[0], low_record_ptr)
	    MOVE(low_record_ptr_pi, new_key_3)
        MOVE(output[0], low_record_ptr)
	    MOVE(low_record_ptr_pi, new_key_2)
        MOVE(output[0], low_record_ptr)
	    MOVE(low_record_ptr_pi, new_key_1)
        MOVE(output[0], low_record_ptr)
	    MOVE(low_record_ptr_pi, new_key_0)

	    # Rest of upper half.
	    # 2x10=20
	    RPT(10)
            MOVE(output[0], low_record_ptr)
	    	MOVE(low_record_ptr_pi, ibuf0)
            MOVE(output[0], low_record_ptr)
	    	MOVE(low_record_ptr_pi, ibuf0)
        END_RPT()

	    # Lower half.
	    # 2x12=24, add one extra at end for 25.
	    RPT(12)
	    	if lastcore
                MOVE(output[0], low_record_ptr)
	    	else
                MOVE(output[1], low_record_ptr)
            end
	    	
	    	if firstcore
	    		MOVE(low_record_ptr_pi, ibuf0)
	    	else
	    		MOVE(low_record_ptr_pi, ibuf1)
	        end	

	    	if lastcore
                MOVE(output[0], low_record_ptr)
	    	else
                MOVE(output[1], low_record_ptr)
            end
	    	
	    	if firstcore
	    		MOVE(low_record_ptr_pi, ibuf0)
	    	else
	    		MOVE(low_record_ptr_pi, ibuf1)
	        end	
        END_RPT()
	    # Copy of above.
	    if lastcore
            MOVE(output[0], low_record_ptr)
	    else
            MOVE(output[1], low_record_ptr)
        end

	    if firstcore
	    	MOVE(low_record_ptr_pi, ibuf0)
	    else
	    	MOVE(low_record_ptr_pi, ibuf1)
	    end 


    # Compare the two stored records to find which is now lower.
    # This block jumps to get_new_key when done.
    # Shared with startup code.
    @label compare_local_records
	    # Check the keys against each other.
	    SUBU(null, local_key_0_0, local_key_1_0)
	    SUBCU(null, local_key_0_1, local_key_1_1)
	    SUBCU(null, local_key_0_2, local_key_1_2)
	    SUBCU(null, local_key_0_3, local_key_1_3)
	    #if(Unsigned0_Signed1){
	    	SUBC(null, local_key_0_4, local_key_1_4, cxs) #Set if carry is true.
	    #}else{
	    #SUBCU(null, local_key_0_4, local_key_1_4, cxs) #Set if carry is true.
	    #}

	    # If carry set, key 0 is lower.
	    MOVI(low_record_ptr_cfg, ag_config_full_record_0, cxt)
	    MOVI(low_key_ptr_cfg, ag_config_key_0, cxt)
	    MOVI(high_record_ptr_cfg, ag_config_full_record_1, cxt)

	    # Otherwise key 1 is lower.
	    MOVI(low_record_ptr_cfg, ag_config_full_record_1, cxf)
	    MOVI(low_key_ptr_cfg, ag_config_key_1, cxf)
	    MOVI(high_record_ptr_cfg, ag_config_full_record_0, cxf)

	    # Ready to get the next record.
	    BRL(get_new_key)

    @label pass_input_to_output
        MOVE(output[0], new_key_4)
        MOVE(output[0], new_key_3)
        MOVE(output[0], new_key_2)
        MOVE(output[0], new_key_1)
        MOVE(output[0], new_key_0)
	    # 5x4=20
	    RPT(5)
            MOVE(output[0], ibuf0)
            MOVE(output[0], ibuf0)
            MOVE(output[0], ibuf0)
            MOVE(output[0], ibuf0)
        END_RPT()
	    # 5x5=25
	    RPT(5)
	    	if firstcore && !lastcore
                MOVE(output[1], ibuf0)
                MOVE(output[1], ibuf0)
                MOVE(output[1], ibuf0)
                MOVE(output[1], ibuf0)
                MOVE(output[1], ibuf0)
	    	elseif (firstcore && lastcore)
                MOVE(output[0], ibuf0)
                MOVE(output[0], ibuf0)
                MOVE(output[0], ibuf0)
                MOVE(output[0], ibuf0)
                MOVE(output[0], ibuf0)
	    	elseif (!firstcore && lastcore)
                MOVE(output[0], ibuf1)
                MOVE(output[0], ibuf1)
                MOVE(output[0], ibuf1)
                MOVE(output[0], ibuf1)
                MOVE(output[0], ibuf1)
	    	else
                  MOVE(output[1], ibuf1)
                  MOVE(output[1], ibuf1)
                  MOVE(output[1], ibuf1)
                  MOVE(output[1], ibuf1)
                  MOVE(output[1], ibuf1)
	        end	
        END_RPT()
	    BRL(get_new_key)

    @label store_new_record_at_low
    	# MOVE(low_record_ptr_pi, ibuf0)
    	# MOVE(low_record_ptr_pi, ibuf0)
    	# MOVE(low_record_ptr_pi, ibuf0)
    	# MOVE(low_record_ptr_pi, ibuf0)
    	# MOVE(low_record_ptr_pi, ibuf0)
    	RPT(25, nop3)
    		MOVE(low_record_ptr_pi, ibuf0)
        END_RPT()
    	RPT(25, nop3)
    		if firstcore
    			MOVE(low_record_ptr_pi, ibuf0)
    		else
    			MOVE(low_record_ptr_pi, ibuf1)
            end
        END_RPT()
    	BRL(back)

    @label flush_0_local_record_with_count
	    # Get count and add 0 for records being passed.
	    # Skip the output for hte last core when not passing flush signals.
	    if lastcore == 0 || lastcore_flush == 1
	    	MOVE(num_records_to_pass, ibuf0_next)
            ADD(output[0], ibuf0, 0)
	    else
	    	MOVE(num_records_to_pass, ibuf0)
	    end 
	    BRL(flush_0_local_record, nop2)

    @label flush_1_local_record_with_count
	    # Get count and add 1 for records being passed.
	    if lastcore == 0 || lastcore_flush == 1
	    	MOVE(num_records_to_pass, ibuf0_next)
            ADD(output[0], ibuf0, 1)
	    else
	    	MOVE(num_records_to_pass, ibuf0)
	    end 
	    BRL(flush_1_local_record)

    @label flush_2_local_record
	    # Get count and add 2 for records being passed.
	    if lastcore == 0 || lastcore_flush == 1
	    	MOVE(num_records_to_pass, ibuf0_next)
            ADD(output[0], ibuf0, 2)
	    else
	    	MOVE(num_records_to_pass, ibuf0)
	    end 

	    # Send low record.
	    # Not expanded due to imem limit.
	    RPT(25, nop3)
            MOVE(output[0], low_record_ptr_pi)
        END_RPT()
	    RPT(25, nop3)
	    	if lastcore
                MOVE(output[0], low_record_ptr_pi)
	    	else
                MOVE(output[1], low_record_ptr_pi)
            end
        END_RPT()
	
    @label flush_1_local_record
    	# Send high record.
    	# 5x5=25
    	RPT(5)
            MOVE(output[0], high_record_ptr_pi)
            MOVE(output[0], high_record_ptr_pi)
            MOVE(output[0], high_record_ptr_pi)
            MOVE(output[0], high_record_ptr_pi)
            MOVE(output[0], high_record_ptr_pi)
        END_RPT()
    	RPT(25, nop3)
    		if lastcore
                MOVE(output[0], high_record_ptr_pi)
    		else
                MOVE(output[1], high_record_ptr_pi)
            end
            END_RPT()
	
    @label flush_0_local_record
	    # Pass records until count of how many to pass goes negative.
	    # Maximum of ~32k records supported.
	    # Start with a 0 check.
	    MOVE(null, num_records_to_pass)
	    BR(start, z)

    @label pass_record
	# Loop unroll the repeats to remove the need for nops.
	# 5x5=25
	RPT(5)
        MOVE(output[0], ibuf0)
        MOVE(output[0], ibuf0)
        MOVE(output[0], ibuf0)
        MOVE(output[0], ibuf0)
        MOVE(output[0], ibuf0)
    END_RPT()
	# 5x5=25
	RPT(5)
		if firstcore && !lastcore
            MOVE(output[1], ibuf0)
            MOVE(output[1], ibuf0)
            MOVE(output[1], ibuf0)
            MOVE(output[1], ibuf0)
            MOVE(output[1], ibuf0)
		elseif firstcore && lastcore
            MOVE(output[0], ibuf0)
            MOVE(output[0], ibuf0)
            MOVE(output[0], ibuf0)
            MOVE(output[0], ibuf0)
            MOVE(output[0], ibuf0)
		elseif !firstcore && lastcore
            MOVE(output[0], ibuf1)
            MOVE(output[0], ibuf1)
            MOVE(output[0], ibuf1)
            MOVE(output[0], ibuf1)
            MOVE(output[0], ibuf1)
		else
            MOVE(output[1], ibuf1)
            MOVE(output[1], ibuf1)
            MOVE(output[1], ibuf1)
            MOVE(output[1], ibuf1)
            MOVE(output[1], ibuf1)
	    end	
    END_RPT()

	# Check count and loop.
	SUBU(num_records_to_pass, num_records_to_pass, 1)
	BRL(pass_record, z, neg)
	BRL(start)

end

# Start_Initialization 
# 	# Verify storage size.
# 	if(m->storage.size() != 3){
# 		__debugbreak();
# 	}
# 
# 	# Set up address generator strides.
# 	MOVI(AG0STRIDE, 0xFF)
# 	MOVI(AG1STRIDE, 1)
# 	MOVI(AG2STRIDE, 1)
# 	
# 	# Set condex 0 to look at carry flag.
# 	MOVI(CXMASK0, 1<<COND_EXEC_MASK_CARRY_BIT)
# 
# End_Initialization 









