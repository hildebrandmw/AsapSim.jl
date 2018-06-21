# Model for dual-clocked fifo.
import Base: write, read

abstract type AbstractFifo end

# A test fifo for testing various methods involving cores.
@with_kw mutable struct TestFifo <: AbstractFifo
    empty :: Bool = false
    full  :: Bool = false
end

isfull(t::TestFifo) = t.full
isempty(t::TestFifo) = t.empty


# Model of the Asap Dual Clocked Fifos.
@with_kw mutable struct DualClockFifo{T} <: AbstractFifo
    # Statistics
    num_reads :: Int = 0
    num_writes :: Int = 0

    # Vector for holding data.
    buffer::Vector{T}

    # Read Side
    rd_rd_pointer :: Int = 1
    rd_wr_pointer :: Int = 1
    wr_rd_pointer :: Int = 1
    wr_wr_pointer :: Int = 1

    # Read side signals
    out_read_valid  :: Bool = false
    out_read_data   :: T    = zero(T)
    in_read_request :: Bool = false

    # Write side signals
    in_write_data    :: T   = zero(T)
    in_write_request ::Bool = false
end

# Constructor
function DualClockFifo(::Type{T}, buffersize::Int) where T
    # Construct the buffer and fall-back to the default values provided
    # by the "with_kw" macro
    buffer = zeros(T, buffersize)
    return DualClockFifo{T}(buffer = buffer)
end

################################################################################
# Methods
################################################################################

function isfull(wr_ptr, rd_ptr, buffersize)
    # Must add 1 to account for 1-based indexing
    buffer_fill = wr_ptr - rd_ptr + 1
    # Do wrap-around logic if needed.
    if wr_ptr < rd_ptr
        buffer_fill += buffersize
    end
    return buffer_fill >= buffersize
end
buffersize(fifo::DualClockFifo) = length(fifo.buffer)



# ------- #
# Reading #
# ------- #
readready(f::DualClockFifo) = f.out_read_valid
readempty(f::DualClockFifo) = f.rd_wr_pointer == f.rd_rd_pointer

read_request(f::DualClockFifo) = (f.in_read_request = true)
read(f::DualClockFifo)      = f.out_read_data

function read_update(f::DualClockFifo)
    # Update write pointer from the write side of the fifo. 
    f.rd_wr_pointer = f.wr_wr_pointer

    # Set the valid signal to "false" where. THere is only one instance
    # where it will be set back to true.
    f.out_read_valid = false

    if f.in_read_request && !readempty(f)
        f.out_read_data = f.buffer[f.rd_rd_pointer]
        f.out_read_valid = true

        # Update read pointer
        f.rd_rd_pointer += 1
        if f.rd_rd_pointer > buffersize(f)
            f.rd_rd_pointer = 1
        end

        # Clear read request
        f.in_read_request = false
    end
end

# ------- #
# Writing #
# ------- #

writeready(f::DualClockFifo) = !isfull(f.wr_wr_pointer, f.wr_rd_pointer, buffersize(f))
writeempty(f::DualClockFifo) = f.wr_wr_pointer == f.wr_rd_pointer

function write(fifo::DualClockFifo{T}, data::T) where T
    # Set the valid signal to true and save the data.
    fifo.in_write_request = true
    fifo.in_write_data = data
end

# Simulate a clock on the "write" side of the fifo.
function write_update(f::DualClockFifo)
    # Update the read pointer from the read-side of the f.
    # TODO: Add delays to model metastability
    f.wr_rd_pointer = f.rd_rd_pointer

    # Check if a write is pending. If so, push through the write.
    if f.in_write_request
        f.buffer[f.wr_wr_pointer] = f.in_write_data
        # Increment the write pointer, wrapping if necessary.
        f.wr_wr_pointer += 1
        if f.wr_wr_pointer > buffersize(f)
            f.wr_wr_pointer = 1
        end

        # Increment counter
        f.num_writes += 1
    end
    # Reset the pending write flag.
    f.in_write_request = false
end
