@testset "Using Test Program" begin

# Note: This program is taken from the aes137_keysub.cpp file.

test_program = MacroTools.@q function aes137_keysub()
	MOVI( dmem[128], 128,   SW)
	MOVI( dmem[129], 65280, SW)
	MOVI( dmem[130], 255,   SW)
	MOVI( dmem[131], 0x7F,  SW)
	
	# Set condex 0 to look at carry flag.
	#MOVI(CXMASK0, 1<<COND_EXEC_MASK_CARRY_BIT)
    MOVI(cxmask0, 2^10)

    @label :main
	RPT(3)
        MOVE( east,  ibuf[0])
        MOVE( east,  ibuf[0])
        MOVE( east,  ibuf[0])
        MOVE( east,  ibuf[0])
    END_RPT()

	RPT(4)
		# Valid alternative for -1 nop, but spams warnings for now.
        MOVE(east,  ibuf_next[0])
        AND(pointer[0], ibuf[0], dmem[131])
		SUB(null, regbp2, dmem[128], cxs1)  #If regbp1 is 0 to 127, set with carry.
		SHR(east,  ptrby, 8, cxf1, nop1)
		AND(east,  aptr0, dmem[130], cxt0)
    END_RPT()

    BRL(:main)
end


end
