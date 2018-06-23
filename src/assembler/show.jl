stringvec(a,b) = "$a[$b]"
# Specialized "show" method for slightly easier viewing.
function Base.show(io::IO, x::AsapInstruction)
    # Specializations on OP Type
    if x.op == :RPT
        show_rpt(io, x)
        return
    end
    show_basic(io, x)
    show_options(io, x)
    show_extra(io, x)
end

function show_basic(io::IO, x::AsapInstruction)
    # Show the op
    print(io, x.op, " ")
    # Print destinations and sources
    print(io, "$(stringvec(x.dest, x.dest_index)) ")
    print(io, "$(stringvec(x.src1, x.src1_index)) ")
    print(io, "$(stringvec(x.src2, x.src2_index)) ")
    return nothing
end

function show_options(io::IO, x::AsapInstruction)
    # Print out instruction options
    if x.nops > 0
        print(io, "nops=$(x.nops) ")
    end
    if x.jump
        print(io, "jump ")
    end
    if x.cxflag != NO_CX
        print(io, "$(stringvec(x.cxflag, x.cxindex)) ")
    end
    if !x.sw
        print(io, "DW ")
    end
end

function show_extra(io::IO, x::AsapInstruction)
    # Extra stuff
    if get(io, :compact, false)
        print(io, x.optype, " ")
        if x.signed
            print(io, "signed ")
        end
        if x.saturate
            print(io, "saturate ")
        end
        if x.dest_is_output
            print(io, "output")
        end
    end
end

function show_rpt(io::IO, x::AsapInstruction)
    # Show the OP
    print(io, x.op, " ")
    print(io, "start=$(repeat_start(x)) stop=$(repeat_end(x)) ")
    print(io, "repeats=$(stringvec(x.src1, x.src1_index)) ")

    show_options(io, x)
    show_extra(io, x)
end
