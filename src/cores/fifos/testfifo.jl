#=
A fifo with a read and write buffer where data can be pre-loaded and recorded.

Useful for testing individual cores without needing to invoke an entire 
simulation.
=#
@with_kw mutable struct TestFifo{T} <: AbstractFifo
    read_data       :: Vector{T} = T[]
    read_pointer    :: Int       = 1
    write_data      :: Vector{T} = T[]

    # Indicate a write is pending for the next "clock cycle"
    write_pending :: Bool = false
    next_write_data :: T  = zero(T)

    # Indicate need to increment read pointer next clock cycle.
    read_increment :: Bool = false
end

isreadready(t::TestFifo) = t.read_pointer <= length(t.read_data)
peek(t::TestFifo) = t.read_data[t.read_pointer]

function read(t::TestFifo)
    t.read_increment = true
    return peek(t)
end

function readupdate!(t::TestFifo)
    if t.read_increment
        t.read_pointer += 1
        t.read_increment = false
    end
    return nothing
end

iswriteready(t::TestFifo) = true

function write(t::TestFifo, data)
    t.write_pending = true
    t.next_write_data = data
    return nothing
end

function writeupdate!(t::TestFifo)
    if t.write_pending
        push!(t.write_data, t.next_write_data)
        t.write_pending = false
    end
    return nothing
end
