# Model of the Asap Dual Clocked Fifos.
@with_kw mutable struct DualClockFifo{T} <: AbstractFifo
    # Statistics
    num_reads  :: Int = 0
    num_writes :: Int = 0

    # Vector for holding data.
    buffer::Vector{T}

    # Pointers
    readside_rd_pointer :: Int = 1
    readside_wr_pointer :: Int = 1
    writeside_rd_pointer :: Int = 1
    writeside_wr_pointer :: Int = 1

    # Read side signals
    out_read_valid    :: Bool = false
    out_read_data     :: T    = zero(T)
    in_read_increment :: Bool = false

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

function getoccupancy(w, r, buffersize)
    occupancy = w - r
    if w < r
        occupancy += buffersize
    end
    return occupancy
end

isfull(w, r, buffersize, reserve) = getoccupancy(w, r, buffersize) >= buffersize - reserve
buffersize(f::DualClockFifo) = length(f.buffer)
reserve(f::DualClockFifo) = 2

function read_occupancy(f::DualClockFifo)
    return getoccupancy(
        f.readside_wr_pointer, 
        f.readside_rd_pointer, 
        buffersize(f),
    )
end

function write_occupancy(f::DualClockFifo)
    return getoccupancy(
        f.writeside_wr_pointer, 
        f.writeside_rd_pointer, 
        buffersize(f),
    )
end

# ------- #
# Reading #
# ------- #
isreadready(f::DualClockFifo) = f.out_read_valid
isreadempty(f::DualClockFifo) = f.readside_wr_pointer == f.readside_rd_pointer

peek(f::DualClockFifo) = f.out_read_data
function read(f::DualClockFifo)
    data = peek(f)
    f.in_read_increment = true
    return data
end

function readupdate!(f::DualClockFifo)
    # Update write pointer from the write side of the fifo. 
    f.readside_wr_pointer = f.writeside_wr_pointer

    if f.out_read_valid && f.in_read_increment
        f.num_reads += 1
    end

    if isreadempty(f) == false && (f.out_read_valid == false || f.in_read_increment == true)
        # Get data to read. 
        f.out_read_data = f.buffer[f.readside_rd_pointer]
        f.out_read_valid = true     

        # Increment read pointer.  
        f.readside_rd_pointer += 1
        if f.readside_rd_pointer > buffersize(f)
            f.readside_rd_pointer = 1
        end

    elseif f.in_read_increment
        f.out_read_valid = false
    end

    f.in_read_increment = false
    return nothing
end

# ------- #
# Writing #
# ------- #

iswriteready(f::DualClockFifo) = !isfull(
    f.writeside_wr_pointer, 
    f.writeside_rd_pointer, 
    buffersize(f),
    reserve(f)
)
iswriteempty(f::DualClockFifo) = f.wr_wr_pointer == f.wr_rd_pointer

function write(fifo::DualClockFifo{T}, data::Integer) where T
    # Set the valid signal to true and save the data.
    fifo.in_write_request = true
    fifo.in_write_data = data
end

# Simulate a clock on the "write" side of the fifo.
function writeupdate!(f::DualClockFifo)
    # Update the read pointer from the read-side of the f.
    # TODO: Add delays to model metastability mitigation
    f.writeside_rd_pointer = f.readside_rd_pointer

    # Check if a write is pending. If so, push through the write.
    if f.in_write_request
        f.buffer[f.writeside_wr_pointer] = f.in_write_data
        # Increment the write pointer, wrapping if necessary.
        f.writeside_wr_pointer += 1
        if f.writeside_wr_pointer > buffersize(f)
            f.writeside_wr_pointer = 1
        end

        # Increment counter
        f.num_writes += 1
    end
    # Reset the pending write flag.
    f.in_write_request = false
end
