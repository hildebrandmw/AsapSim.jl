# A collection of simple programs that more fully test aspects of the processor.

# This function will read numbers from input fifo 0. It will store a single
# number at dmem 0
#
# If a value it reads is less than the value stored in DMEM, it will forward
# the newly read value to output 0
#
# Otherwise, it will swap the two numbers and write the old number stored in
# DMEM to output 0
@asap4asm function dumb_sort()
    @label start
        # Read from FIFO 0 and store the result into DMEM 1
        MOVE(dmem[1], ibuf[0])
        # Subtract DMEM 1 from DMEM 0. This will set the "negative" alu flag if
        # dmem[1] > dmem[0]. Branch based on the outcome of this comparison.
        SUBU(null, dmem[0], bypass[1])
        BRL(swap, N, j)
        # Write out DMEM[1]
        NOP()
        NOP()
        NOP()
        MOVE(output[0], dmem[1])
        BRL(start)


    @label swap
        # Take advantage of latency in the pipeline to swap the two entries in
        # DMEM
        MOVE(dmem[1], dmem[0])
        MOVE(dmem[0], dmem[1], nop3)
        # Add NOPs to ensure writeback happens.
        NOP()
        BRL(back)
end
