# Programs to test writing to destinations.

# Write to hardware pointers.
@asap4asm function pointer_write_1()
    MOVI(set_pointer[0], 1)
    MOVI(set_pointer[1], 2)
    MOVI(set_pointer[2], 3)
    MOVI(set_pointer[3], 4)
end

# Write to address generators.
#
# Start is the lower 8 bits and stop is the upper 16 bits.
@asap4asm function address_generator_write_1()
    # Set start to 10, stop to 20 and stride to 3
    MOVI(ag_start[0], ((20 << 8) | 10))
    MOVI(ag_stride[0], 3)

    # Set start to 0, stop to 255, and stride to "-1"
    MOVI(ag_start[1], 255 << 8)
    MOVI(ag_stride[1], 0xFF)

    # Set start to 100, stride to 1
    MOVI(ag_start[2], 100)
    MOVI(ag_stride[2], 1)
end

# Write to CX Mask
@asap4asm function cxmask_write_1()
    MOVI(cxmask[0], 0xFFFF)
end

# Write to OBUF mask - just write all 1's.
@asap4asm function obufmask_write_1()
    MOVI(obuf_mask, 0xFF)
end
