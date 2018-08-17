

#Function(Snakesort)

#define First_Core            m->storage[0]
#define Last_Core             m->storage[1]
#define max_weights           m->storage[2]
#define weights_mode          m->storage[3]


# Start_Initialization
# // Verify storage size.
# if (m->storage.size() != 4) {
#   __debugbreak();
# }

function initialize_snakesort2(core)
    weights_ptr_pi      = ag0pi
    weights_ptr         = ag0
    weights_ptr_config  = AG0START
    weights_ptr_config1 = AG1START
    weights_ptr_im      = AG2START
    
    weights_mode_int = Loc(AsapSim.DMEM, 255)
    ag_config_weights = ((max_weights<<8) + 1)
    ag_config_im = (((max_weights+20)<<8) + 21)

    # Set up address generator strides.
    MOVI(AG0STRIDE, 1)
    MOVI(weights_ptr_config, ag_config_weights)
    MOVI(weights_ptr_config1, ag_config_weights)
    MOVE(weights_mode_int, weights_mode)
    MOVI(weights_ptr_im, ag_config_im)
    MACCL(null, 0, 0)
end


@asap4asm function snakesort2(firstcore, lastcore, max_weights, weights_mode)
    weights_ptr_pi      = :ag0pi
    weights_ptr         = :ag0
    weights_ptr_config  = Loc(AsapSim.AG_START, 0)
    weights_ptr_config1 = Loc(AsapSim.AG_START, 1)
    weights_ptr_im      = Loc(AsapSim.AG_START, 2)
    
    weights_mode_int = Loc(AsapSim.DMEM, 255)
    ag_config_weights = ((max_weights<<8) + 1)
    ag_config_im = (((max_weights+20)<<8) + 21)

    @label start
    if (weights_mode == 1)
        RPT(max_weights,nop3)
            MOVE(ag0pi, ibuf0,nop3)
        END_RPT()
        MOVI(weights_mode, 0)
    end
    
    NOP(nop3)
    # if (Last_Core) {
    #     printf("\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d", Dmem[1], Dmem[2], Dmem[3], Dmem[4], Dmem[5], Dmem[6], Dmem[7], Dmem[8], Dmem[9], Dmem[10], Dmem[11], Dmem[12]);
    # }
    
    MOVE(null, ibuf0)
    
    @label pass_weights_downstream
    if (!lastcore)
        MOVE(output[0], ibuf0)
        BR(pass_weights_downstream, Z, neg)
        MOVE(null, ibuf0_next)
        BR(pass_weights_downstream, Z, neg)
    end
    
    
    
    if (!lastcore)
        MOVE(output[0], ibuf0)
    end
    
    if (lastcore)
        MOVE(null, ibuf0)
    end
    RPT(max_weights,nop3)
        MOVE(ag2pi, ibuf0_next, nop3)
        MACL(null, ag1pi,ibuf0,nop3)
    END_RPT()
    NOP(nop3)
    @label pass_im_downstream
    if (!lastcore)
        MOVE(output[0], ibuf0)
        BR(pass_im_downstream, Z, neg)
    end
    
    if (lastcore)
        MOVI(output[0], acc)
    end
    
    NOP(nop3)
    # if (Last_Core) {
    #     printf("\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d", Dmem[21], Dmem[22], Dmem[23], Dmem[24], Dmem[25], Dmem[26], Dmem[27], Dmem[28], Dmem[29], Dmem[30], Dmem[31], Dmem[32]);
    # }
    BRL(start)
end


