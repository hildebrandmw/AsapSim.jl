@testset "Testing IO" begin
    # Create an InputHandler and an OutputHandler. Connect the two of them 
    # together and make sure that data gets piped from the input to the output.

    fifo = AsapSim.DualClockFifo(Int64,10)

    input = AsapSim.InputHandler{Int64,typeof(fifo)}(output = fifo)
    output = AsapSim.OutputHandler{Int64,typeof(fifo)}(input = fifo)

    input.data = rand(Int64, 100)

    for i in 1:200
        update!(output)
        update!(input)
    end

    @test output.data == input.data
end
