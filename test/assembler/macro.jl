@testset "Testing Random Misc. Stuff" begin
    # Testing my convenience macro.
    kwargs = []
    a = 1; b = 2; c = 3;
    AsapSim.@pairpush! kwargs a b c
    @test kwargs == [:a => a, :b => b, :c => c]


end



# @testset "Testing Expansion" begin
#     # Test the expansion of AsapIntermediate instructions
# end
