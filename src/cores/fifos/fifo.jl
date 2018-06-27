# Model for dual-clocked fifo.
import Base: write, read

abstract type AbstractFifo end

##################
# Fifo Interface #
##################

"""
    isreadready(f::AbstractFifo)

Return `true` if `read(f)` may be called and will return valid read data.
"""
isreadready(f::AbstractFifo) = false

"""
    peek(f::AbstractFifo)

Return the top element of the read side of the fifo. Must not change that read
element. That is, `peek()` must be save to call multiple times in a row.
"""
peek(f::AbstractFifo) = nothing

"""
    read(f::AbstractFifo)

Return the top element of the read side of the fifo. Mark the fifo so it will
be updated to the next element on the next call to `readupdate!(f)`.
"""
read(f::AbstractFifo) = nothing

"""
    readupdate!(f::AbstractFifo)

Update the read side of `f`. Usually analogous to "clocking" the read side of
the fifo.
"""
readupdate!(f::AbstractFifo) = nothing

"""
    iswriteready(f::AbstractFifo)

Return `true` if `write(f)` followed by `writeupdate!` will be successful.
"""
iswriteready(f::AbstractFifo) = false

"""
    write(f::AbstractFifo, data)

Send data to `f` to store on the next call to `writeupdate!(f)`.
"""
write(f::AbstractFifo, data) = nothing

"""
    writeupdate!(f::AbstractFifo)

Update the write side of `f`. Usually analogous to "clocking" the write side
of the fifo.
"""
writeupdate!(f::AbstractFifo, data) = nothing

# A test fifo for testing various methods involving cores.
@with_kw mutable struct EmptyFullFifo <: AbstractFifo
    empty :: Bool = false
    full  :: Bool = false
end

isreadready(t::EmptyFullFifo) = !t.empty
iswriteready(t::EmptyFullFifo) = !t.full
