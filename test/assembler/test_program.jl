@testset "Using Test Program" begin

# Note: This program is taken from the aes137_keysub.cpp file.
returneight() = 8

test_program = MacroTools.@q function aes137_keysub()
    # Declare a local variable. Should not be interpreted as an instruction
    localvar = 255

	MOVI( dmem[130], localvar, SW)      # I1
	MOVI( dmem[131], 0x7F,  DW)         # I2
    MOVI(cxmask0, 2^10)                 # I3

    @label :main    #Not an instruction, but should be recognized as I6
	RPT(3)                          # I4 Start: 5 End: 9
        MOVE( output[0],  ibuf[0])  # I5
        MOVE( east,  ibuf[0])       # I6
        MOVE( east,  ibuf[0])       # I7
        MOVE( east,  ibuf[0])       # I8
    END_RPT()                       #       imm9

    BR(:dummy)          # I9 -- imm10
    @label :GOBACK      # Belongs to I10

	RPT(4)  # I10 Start: 11 End 15  imm11
        MOVE(east,  ibuf_next[0])  # I11 -- imm12
        AND(pointer[0], ibuf[0], dmem[131]) # I12 -- imm13
		SUB(null, regbp2, dmem[128], cxs1)  # I13 -- imm14
        SHR(east,  ptrby, returneight(), cxf1, nop1)    # I14 -- imm15
		AND(east,  aptr0, dmem[130], cxt0)  # I15 -- imm16
    END_RPT() # -- imm16

    BRL(:main) # I16 -- imm18

    @label :dummy   # Belongs to I17
    BRL(:GOBACK)    # I17 -- imm19
end

# Going to test various parts of the assembly process.
split_def = splitdef(test_program)

# First, get the intermediate instructions directly from the expression.
intermediates = AsapSim.getassembly(split_def[:body])

@test length(intermediates) == 19
@test intermediates[1] == AsapSim.AsapIntermediate(:MOVI, [:(dmem[130]), :localvar, :SW])

end
