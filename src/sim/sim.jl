#=
Create wrappers for cores that will interact with DES to create the simulation
environment.
=#
mutable struct SimWrapper{T}
    core :: T
    callback :: Callback
    visits :: Int
end

SimWrapper(core :: T) where T = SimWrapper(core, Callback(), 0)

core(s::SimWrapper) = s.core
getcallback(s::SimWrapper) = s.callback
setcallback!(s::SimWrapper, c::Callback) = s.callback = c

function update!(sim, wrapper :: SimWrapper)
    update!(core(wrapper))
    schedule!(sim, getcallback(wrapper), clockperiod(core(wrapper)))
    wrapper.visits += 1
    return nothing
end

function wrap(core :: T) where T
    wrapper = SimWrapper(core)
    setcallback!(wrapper, Callback(sim -> update!(sim, wrapper)))

    return wrapper
end

DES.schedule!(sim::Simulation, wrapper::SimWrapper) = schedule!(sim, getcallback(wrapper), 0)
