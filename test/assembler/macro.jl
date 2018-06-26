const test_int = 10
const test_sym = :dmem
const test_loc_array = [Loc(:dmem, 10)]

@testset "Testing Random Misc. Stuff" begin
    quot = Meta.quot

    # Testing my convenience macro.
    kwargs = []
    a = 1; b = 2; c = 3;
    AsapSim.@pairpush! kwargs a b c
    @test kwargs == [:a => a, :b => b, :c => c]

    extract_loc = AsapSim.extract_loc
    @test eval(extract_loc(1)) == Loc(:immediate, 1)
    # Test reserved reference
    @test eval(extract_loc(:test_int)) == Loc(:immediate, 10)
    @test eval(extract_loc(:test_sym)) == Loc(:dmem, -1)
    # Test reserved reference
    @test eval(extract_loc(:ibuf0)) == Loc(:ibuf, 0)

    # --- Test expressions --- #

    # Test an expression that is reserved
    @test eval(extract_loc(1 + 1 + 1)) == Loc(:immediate, 3)
    @test eval(extract_loc(:(dmem[0]))) == Loc(:dmem, 0)
    @test eval(extract_loc(:(test_loc_array[1]))) == test_loc_array[1]
    @test eval(extract_loc(:(dmem[test_int]))) == Loc(:dmem, test_int)
end



# @testset "Testing Expansion" begin
#     # Test the expansion of AsapIntermediate instructions
# end
