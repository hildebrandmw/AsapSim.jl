const test_int = 10
const test_sym = AsapSim.DMEM
const test_loc_array = [Loc(AsapSim.DMEM, 10)]

@testset "Testing Random Misc. Stuff" begin
    quot = Meta.quot

    # Testing my convenience macro.
    kwargs = []
    a = 1; b = 2; c = 3;
    AsapSim.@pairpush! kwargs a b c
    @test kwargs == [:a => a, :b => b, :c => c]

    # --- Extract Loc --- #

    extract_loc = AsapSim.extract_loc

    # Passing an integer directly to extract_loc should result in a immediate
    # style Loc.
    @test eval(extract_loc(1)) == Loc(AsapSim.IMMEDIATE, 1)

    # If a symbol is passed to extract_loc that is not a reserved symbol, we
    # should get the expression :(Loc(test_int)). Since test_int is a Int,
    # when that expression is Evaled, we get an immediate Loc with the value
    # of test_int.
    @test eval(extract_loc(:test_int)) == Loc(AsapSim.IMMEDIATE, 10)

    # If instead the symbol given to extract_loc resolved to a Symbol, the
    # constructor Loc(x::Symbol) will be called when evaled.
    @test eval(extract_loc(:test_sym)) == Loc(AsapSim.DMEM, -1)

    # If we pass a symbol that is reserved, make sure we get the corresponding
    # Loc correctly.
    @test eval(extract_loc(:ibuf0)) == Loc(AsapSim.IBUF, 0)

    # If we pass "extract_loc" an expression that resolves to an integer, it
    # should keep that expression intact so that when it is evaluated, the
    # correct computation takes place.
    @test eval(extract_loc(:(1 + 1 + 1))) == Loc(AsapSim.IMMEDIATE, 3)

    # If a valid Source / Destination is given with a literal index, make sure
    # that this is discovered and a valid Src/Dest enum is created.
    @test eval(extract_loc(:(dmem[0]))) == Loc(AsapSim.DMEM, 0)

    # If an expression for an index is given where the item being index is
    # NOT a valid Src/Dest pair, it will be passed straight through to the
    # constructor of Loc. In this case, test_loc_array[1] IS a Loc, so we should
    # just get the same thing back.
    @test eval(extract_loc(:(test_loc_array[1]))) == test_loc_array[1]

    # Finally, test that if we pass a valid reference without a literal index
    # that this index is correctly extracted when the expression is Evaled.
    @test eval(extract_loc(:(dmem[test_int]))) == Loc(AsapSim.DMEM, test_int)

    # --------------------------------------------------- #
    # --- Test some of the simpler macros for correctness #
    # --------------------------------------------------- #

    expr = MacroTools.@q function test(branch)
        if branch
            return 10
        end
    end

    # Add a program vector initialization and return statement.
    split_expr = splitdef(expr)
    function_body = split_expr[:body]
    program_vector_sym = gensym("program")
    # Add an initializer for an empty vector of InstructionLabelTarget
    AsapSim.startvector!(function_body, program_vector_sym)

    # Replace returns. The actual invocation of this function needs to be a call
    # to "assemble" - but that's kind of hard to test. Rather, just use the
    # "identity" function to get the empty vector directly.
    function_body = AsapSim.replace_returns(
        function_body,
        program_vector_sym;
        return_fn = identity
    )
    # Remake the function and "eval" it.
    split_expr[:body] = function_body
    eval(MacroTools.combinedef(split_expr))

    # The function "test" should now be available.
    # If we call it (regardless of what we give for "branch", we should recieve
    # an empty vector of InstructionLabelTarget.
    @test test(false) == AsapSim.InstructionLabelTarget[]
    @test test(true) == AsapSim.InstructionLabelTarget[]
end

# TODO: getkwargs
# TODO: replace_instructions

macro evalexpr(ex)
    expr = eval(ex)
    return esc(:($expr))
end

@testset "Testing \"replace_instructions\"" begin
    # First, try a simple move instructions. Do this by evaling the
    # returned expression because comparing expressions is REALLY hard.
    let program = AsapSim.InstructionLabelTarget[]
        @evalexpr AsapSim.replace_instructions(:(MOVE(dmem[1], 1)), :program)

        @test length(program) == 1
        # Get the instruction type.

        inst = first(program).instruction
        expected_instruction = AsapInstructionKeyword(
            op = AsapSim.MOVE,
            dest = Loc(AsapSim.DMEM, 1),
            src1 = Loc(AsapSim.IMMEDIATE, 1),
            optype = AsapSim.ALU_TYPE,
        )

        @test inst == expected_instruction
        @test first(program).label == nothing
        @test first(program).branch_target == nothing
    end

    # Test a little more complicated program.
    let program = AsapSim.InstructionLabelTarget[]
        @evalexpr AsapSim.replace_instructions(quote
            @label test
                ADDCS(output[0], ibuf0, dmem[10], cxs0)
                BR(test, j, Z, neg)

            # Make sure stuff like this is left alone.
            x = 10

            @label another
                BRL(back, nop3)
        end, :program)

        # Make sure the assignment to "x" is seen.
        @test x == 10

        # Should be 3 instructions.
        @test length(program) == 3

        # Manually check the label and branch target vectors.
        branch_targets = [i.branch_target for i in program]
        labels = [i.label for i in program]

        # Only branch instructions should have branch targets.
        @test branch_targets == [nothing, :test, :back]
        @test labels == [:test, :test, :another]

        # Test that the instructions were decoded correctly.
        expected_add = AsapInstructionKeyword(
            op = AsapSim.ADDCS,
            dest = Loc(AsapSim.OUTPUT, 0),
            src1 = Loc(AsapSim.IBUF, 0),
            src2 = Loc(AsapSim.DMEM, 10),
            cxflag = AsapSim.CX_SET,
            cxindex = 0,
            signed = true,
            saturate = true,
            optype = AsapSim.ALU_TYPE,
        )
        @test program[1].instruction == expected_add

        expected_br = AsapInstructionKeyword(
            op = AsapSim.BR,
            # Bits 1 and 12 should be set
            src1 = Loc(AsapSim.IMMEDIATE, (1 << 1) | (1 << 12)),
            jump = true,
            optype = AsapSim.BRANCH_TYPE,
        )
        @test program[2].instruction == expected_br

        expected_brl = AsapInstructionKeyword(
            op = AsapSim.BRL,
            # Unconditional, so bit 11 should be set.
            src1 = Loc(AsapSim.IMMEDIATE, 1 << 11),
            nops = 3,
            isreturn = true,
            optype = AsapSim.BRANCH_TYPE,
        )
        @test program[3].instruction == expected_brl
    end
end

@testset "Testing Assembler" begin
    # Note: This program is taken from the aes137_keysub.cpp file.
    returneight() = 8
    instructions = InstructionLabelTarget[]

    # Push a bunch of instructions to the program.
    @evalexpr AsapSim.replace_instructions(quote
        # Declare a local variable. Should not be interpreted as an instruction
        localvar = 255

    	MOVI( dmem[130], localvar, SW)          # I1

        @label main
    	RPT(3)                                  # I2
            MOVE(output[0],  ibuf[0])           # I3
        END_RPT()

        BR(GOBACK)                              # I4

        @label GOBACK
    	RPT(4)                                  # I5
            MOVE(output[0],  ibuf_next[0])      # I6
            AND(pointer[0], ibuf[0], dmem[131]) # I7
        END_RPT()

        BRL(main)                               # I8

        BRL(back)                               # I9
    end, :instructions)

    @test length(instructions) == 11

    # Get out the constituent parts of the InstructionLabelTarget vector
    program = [i.instruction for i in instructions]
    labels = [i.label for i in instructions]
    branch_targets = [i.branch_target for i in instructions]

    # Make sure instructions got decorded correctly.
    @test program[1].op == AsapSim.MOVI
    @test program[2].op == AsapSim.RPT
    @test program[3].op == AsapSim.MOVE
    @test program[4].op == AsapSim.END_RPT
    @test program[5].op == AsapSim.BR
    @test program[6].op == AsapSim.RPT
    @test program[7].op == AsapSim.MOVE
    @test program[8].op == AsapSim.AND
    @test program[9].op == AsapSim.END_RPT
    @test program[10].op == AsapSim.BRL
    @test program[11].op == AsapSim.BRL

    # Make sure the label dictionary is created correctly.
    labeldict = AsapSim.makelabeldict(labels)
    @test labeldict[:main] == 2
    @test labeldict[:GOBACK] == 6

    # Test that handlerpt! does what it's supposed to.
    AsapSim.handle_rpt!(instructions)

    program = [i.instruction for i in instructions]
    @test program[1].op == AsapSim.MOVI
    @test program[2].op == AsapSim.RPT
    @test program[3].op == AsapSim.MOVE
    @test program[4].op == AsapSim.BR
    @test program[5].op == AsapSim.RPT
    @test program[6].op == AsapSim.MOVE
    @test program[7].op == AsapSim.AND
    @test program[8].op == AsapSim.BRL
    @test program[9].op == AsapSim.BRL

    # Make sure the first RPT starts and ends at instruction3
    @test AsapSim.repeat_start(program[2]) == 3
    @test AsapSim.repeat_end(program[2]) == 3

    # Make sure the second repeat starts at instruction 6 and ends at 7
    @test AsapSim.repeat_start(program[5]) == 6
    @test AsapSim.repeat_end(program[5]) == 7

    # Feed this program into the "assemble" function. CHeck that branch
    # targets are resolved correctly.
    #
    # NOTE: handle_rpt! should be save to call multiple times, so we don't
    # really have to worry about that messing things up.
    asap_program = AsapSim.assemble(instructions)

    # Check that branches resolved correctly.
    @test AsapSim.branch_target(asap_program.instructions[4]) == 5
    @test AsapSim.branch_target(asap_program.instructions[8]) == 2
    # This is the return - it's branch target should not have been modified.
    @test AsapSim.branch_target(asap_program.instructions[9]) == -1
end
