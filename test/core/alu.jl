# Test suite for the ALU, saturator, MAC, and branch evaluator.

mutable struct TestBundle
    src1 :: Vector{Int16}
    src2 :: Vector{Int16}
    cin :: Vector{Bool}
end
TestBundle() = TestBundle(Int16[], Int16[], Bool[])

@testset "ALU Tests" begin
    # Set this flag to benchmark ALU Operations
    benchmark = false

    # This is going to be painful, but necessary. Have to check all of the ALU 
    # type ops

    # Need to set up some preliminary data structures that will be used for
    # all of the tests.

    # Alias some commands for more convenient testing.
    CondExec        = AsapSim.CondExec
    PipelineEntry   = AsapSim.PipelineEntry
    ALUFlags        = AsapSim.ALUFlags
    AsapInstruction = AsapSim.AsapInstructionKeyword

    # 2-long vector for conditional execution.
    condexec = [CondExec(), CondExec()]

    # Template Pipeline Stage. Since they are mutable, we can just mutate this
    # one to perform the different tests.
    stage = PipelineEntry()


    # Functions for performing various tests
    function op_tester(
            ::Type{T},
            op, 
            stage, 
            test :: TestBundle;
            benchmark = false
        ) where T
        # Instantiate new ALU Flags

        for (src1v, src2v, cin) in zip(test.src1, test.src2, test.cin)
            # Set the src1_value and src2_value fields
            # First, convert the source values to 16 bit unsigned numbers
            # (will error if the conversion is inexact)
            #
            # Then reinterpret to Int16 since that is the desired type of the
            # pipe stage fields.
            stage = AsapSim.reconstruct(stage, AsapSim.SRC(src1v, src2v))

            # Edit the carry flag.
            aluflags = ALUFlags(cin, false, false, false)
            if benchmark
                b = @benchmark AsapSim.stage4_alu($stage, $aluflags, $condexec)
                println("Average time for $(stage.instruction.op): $(mean(b.times))")
            end
            result, newflags = AsapSim.stage4_alu(stage, aluflags, condexec)

            # Next the "op" twice so it works correctly if op is "+" or "-".
            if T == Unsigned
                # Do 2's complement arithmetic on the operands, then convert
                # everything to "Unsigned" for prettier printing.
                expected_result = reinterpret(UInt16, op(op(src1v, src2v), Int16(cin)))
                @test reinterpret(UInt16, result) == expected_result

                # Convert the input operands to UInt64. Compute whether there
                # should be a carry out and test for it.
                #
                # Note that since we converted to UInt64, if subtraction yields
                # a carry-out, the following logic should still be correct.
                src1_full = UInt(reinterpret(UInt16, src1v))
                src2_full = UInt(reinterpret(UInt16, src2v))
                full_result = op(op(src1_full, src2_full), UInt(cin))

                # If the full result is greater than the maximum expressible
                # value of a unsigned 16 bit number.
                expected_carry = full_result > typemax(UInt16)
                @test newflags.carry == expected_carry

            elseif T == Signed
                expected_result = op(op(src1v, src2v), Int16(cin))
                @test result == expected_result

                # Compute if overflow should have happened by performing
                # the same operation with full 64-bit numbers and checking if
                # the result is expressible in 16 bits.
                full_result = op(op(Int64(src1v), Int64(src2v)), Int64(cin))
                expected_overflow = full_result > typemax(Int16) || full_result < typemin(Int16)
                @test newflags.overflow == expected_overflow
            end
        end
    end


    test = TestBundle()

    @testset "Arithmetic" begin
        max_s = typemax(Int16)
        min_s = typemin(Int16)

        # Lets start going down the list.

        # --- ADDSU / ADDU ---
        stage = PipelineEntry(AsapInstruction(op = :ADDSU))

        # Loop through a few operand pairs, making sure to have a mix of numbers 
        # that would be negative 16 bit values is interpreted as signed numbers.
        # Use a full 64-bit number for comparison.
        test.src1 = reinterpret.(Int16, [0x0000, 0xFFFF, 0x8001])
        test.src2 = reinterpret.(Int16, [0x0000, 0xFFFF, 0x1234])
        test.cin  = [false, false, false]
        op_tester(Unsigned, +, stage, test, benchmark = benchmark)

        # --- ADDCSU / ADDCU ---
        stage = PipelineEntry(AsapInstruction(op = :ADDCSU))
        test.src1 = reinterpret.(Int16, [0xFFFE, 0xFFFF, 0x0000, 0x0001, 0x0001])
        test.src2 = reinterpret.(Int16, [0x0000, 0x0000, 0x0000, 0xFFFF, 0xFFFE])
        test.cin  = [true, true, true, false, true]
        op_tester(Unsigned, +, stage, test, benchmark = benchmark)

        # --- ADDS / ADD ---
        stage = PipelineEntry(AsapInstruction(op = :ADD))
        test.src1 = [ -1  , max_s , min_s,    0]
        test.src2 = [min_s, 3     , max_s, min_s] 
        test.cin  = zeros(Bool, length(test.src1))
        op_tester(Signed, +, stage, test, benchmark = benchmark)
    end


end
