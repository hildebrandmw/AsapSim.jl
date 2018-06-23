@testset "Using Test Program" begin

# Note: This program is taken from the aes137_keysub.cpp file.
returneight() = 8

# Test program to check assembler is working right. The code below should be
# transformed into a vector of AsapIntermediates. The first pass will store
# the "END_RPT()" functions, then a second pass will remove those and store
# the end address for the leading RPT instructions.
#
# Instructions will be annotated with their final instruction number (IN) and
# their intermediate instruction number (immN)
test_program = MacroTools.@q function aes137_keysub()
    # Declare a local variable. Should not be interpreted as an instruction
    localvar = 255

	MOVI( dmem[130], localvar, SW)      # I1 -- imm1
	MOVI( dmem[131], 0x7F,  DW)         # I2 -- imm2
    MOVI(cxmask0, 2^10)                 # I3 -- imm3

    @label :main    # Should be applied to I4
	RPT(3)                          # I4 -- imm4  Start: 5 End: 9
        MOVE( output[0],  ibuf[0])  # I5 -- imm5
        MOVE( east,  ibuf[0])       # I6 -- imm6
    END_RPT()                       #    -- imm7

    BR(:dummy)                      # I7 -- imm8
    @label :GOBACK      # Belongs to I8

	RPT(4)                          # I8 -- imm9 Start: 9 End 13
        MOVE(east,  ibuf_next[0])   # I9 -- imm10
        AND(pointer[0], ibuf[0], dmem[131])             # I10 -- imm11
		SUB(null, regbp2, dmem[128], cxs1)              # I11 -- imm12
        SHR(east,  ptrby, returneight(), cxf1, nop1)    # I12 -- imm13
		AND(east,  aptr0, dmem[130], cxt0)              # I13 -- imm14
    END_RPT()                                           #     -- imm15

    BRL(:main)      # I14 -- imm16

    @label :dummy   # Belongs to I15
    BRL(:GOBACK)    # I15 -- imm17
end

# Going to test various parts of the assembly process.
split_def = splitdef(test_program)

# First, get the intermediate instructions directly from the expression.
intermediates = AsapSim.getassembly(split_def[:body])

# Alias constructer for conciseness.
AI = AsapSim.AsapIntermediate



@test length(intermediates) == 17

# Instructions 1 - 5
@test intermediates[1] == AI(:MOVI, [:(dmem[130]), :localvar, :SW])
@test intermediates[2] == AI(:MOVI, [:(dmem[131]), 0x7F, :DW])
@test intermediates[3] == AI(:MOVI, [:cxmask0, :(2^10)])
# this instruction should have a label attached to it.
@test intermediates[4] == AI(:RPT,  [3], Symbol(":main"))
@test intermediates[5] == AI(:MOVE, [:(output[0]), :(ibuf[0])])

# Instructions 6 - 10
@test intermediates[6] == AI(:MOVE, [:(east), :(ibuf[0])])
@test intermediates[7] == AI(:END_RPT, [])
@test intermediates[8] == AI(:BR, [QuoteNode(:dummy)])
@test intermediates[9] == AI(:RPT, [4], Symbol(":GOBACK"))
@test intermediates[10] == AI(:MOVE, [:(east), :(ibuf_next[0])])

# Instructions 11 - 15
@test intermediates[11] == AI(:AND, [:(pointer[0]), :(ibuf[0]), :(dmem[131])])
@test intermediates[12] == AI(:SUB, [:null, :regbp2, :(dmem[128]), :cxs1])
@test intermediates[13] == AI(:SHR, [:east, :ptrby, :(returneight()), :cxf1, :nop1])
@test intermediates[14] == AI(:AND, [:east, :aptr0, :(dmem[130]), :cxt0])
@test intermediates[15] == AI(:END_RPT, [])

# Instructions 16-17
@test intermediates[16] == AI(:BRL, [QuoteNode(:main)])
@test intermediates[17] == AI(:BRL, [QuoteNode(:GOBACK)], Symbol(":dummy"))

# Run the pass to resolve repeat blocks and test that the start and end points
# for the repeat blocks in the testprogram are correct.
AsapSim.handle_rpt!(intermediates)

# Two RPT instructions should have been removed.
@test length(intermediates) == 15
@test intermediates[4].repeat_start == 5
@test intermediates[4].repeat_end == 6
@test intermediates[8].repeat_start == 9
@test intermediates[8].repeat_end == 13

# Extract the addresses of labels.
label_dict = AsapSim.findlabels(intermediates)

@test length(label_dict) == 3
@test haskey(label_dict, Symbol(":main"))
@test label_dict[Symbol(":main")] == 4
@test haskey(label_dict, Symbol(":dummy"))
@test label_dict[Symbol(":dummy")] == 15
@test haskey(label_dict, Symbol(":GOBACK"))
@test label_dict[Symbol(":GOBACK")] == 8

# Test to make sure that single-line programs parse correctly.
# Originally, if a program consisted of a single instruction, that instruction
# would be duplicated accidentally.
@asap4asm function single_function()
    MOVI(dmem[0], 100)
end
@test length(single_function()) == 1


end
