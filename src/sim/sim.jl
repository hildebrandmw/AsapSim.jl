#=
Create wrappers for cores that will interact with DES to create the simulation
environment.
=#
mutable struct SimWrapper{T}
    obj :: T
    handle :: Int
    visits :: Int
end

SimWrapper(obj) = SimWrapper(obj, 0, 0)

isregistered(s::SimWrapper) = gethandle(s) > 0
unwrap(s::SimWrapper) = s.obj
gethandle(s::SimWrapper) = s.handle
sethandle!(s::SimWrapper, h::Int) = s.handle = h

function update!(sim, wrapper :: SimWrapper)
    update!(unwrap(wrapper))
    schedule!(sim, gethandle(wrapper), clockperiod(unwrap(wrapper)))
    wrapper.visits += 1
    return nothing
end

function wrap!(sim, obj :: T) where T
    wrapper = SimWrapper(obj)
    handle = register!(sim, sim -> update!(sim, wrapper))
    sethandle!(wrapper, handle) 

    return wrapper
end

LightDES.schedule!(sim::Simulation, wrapper::SimWrapper) = schedule!(sim, gethandle(wrapper), 0)
