@testset "Testing Assembler Helper Functions" begin
    # Various flavors of "extract_ref". The goal of these functions is to get
    # a source or destination as well as a corresponding value if necessary.
    @test AsapSim.extract_ref(100) == (:immediate, 100)
    @test AsapSim.extract_ref(UInt(100)) == (:immediate, 100)
    @test AsapSim.extract_ref(:anything) == (:anything, -1)
    @test AsapSim.extract_ref(:(anything[10])) == (:anything, 10)

    # Test the branch mask constructor

    # Expect bits 0 and 12 to be set. Expect :csx0 and :anything to be left.
    args = [:N, :csx0, :N, :neg, :anything]
    @test AsapSim.make_branch_mask(args) == 1 | 1 << 12
    # Check that the branch-specific args have been removed to avoid passing 
    # them to the generic argument parser.
    @test args == [:csx0, :anything]
end


# @testset "Testing Expansion" begin
#     # Test the expansion of AsapIntermediate instructions
# end
