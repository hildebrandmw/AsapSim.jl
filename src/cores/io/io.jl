#=
An core that can serve as an array input.
=#
@with_kw mutable struct InputHandler{T, F <: AbstractFifo}
    # Clock period of the input.
    clockperiod :: Int = 1

    # Data reserve to write out.
    data :: Vector{T} = T[]
    pointer :: Int = 1

    # Output fifo.
    output :: F = F()
end


function update!(c::InputHandler)
    # If there is data left to write, try to write it to the output.
    if checkbounds(Bool, c.data, c.pointer) && iswriteready(c.output)
        write(c.output, c.data[c.pointer])
        c.pointer += 1

        if mod(c.pointer, 500) == 0
            println("On input $(c.pointer) of $(length(c.data))")
        end
    end
    writeupdate!(c.output)
end


@with_kw mutable struct OutputHandler{T, F <: AbstractFifo}
    clockperiod :: Int = 1
    data :: Vector{T} = T[]
    stoplength :: Int = 0
    input :: F = F()
end


function update!(c::OutputHandler)
    # If new data is available, read from the input.
    if isreadready(c.input)
        push!(c.data, read(c.input))

        if (0 < c.stoplength) && (c.stoplength <= length(c.data))
            throw(StopSimulation())
        end
    end
    # Update input.
    readupdate!(c.input)
end

clockperiod(c::Union{InputHandler,OutputHandler}) = c.clockperiod
