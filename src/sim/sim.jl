#=
Create wrappers for cores that will interact with DES to create the simulation
environment.
=#
mutable struct SimWrapper{T}
    obj :: T
    callback :: Callback
    visits :: Int
end

SimWrapper(obj) = SimWrapper(obj, Callback(), 0)

unwrap(s::SimWrapper) = s.obj
callback(s::SimWrapper) = s.callback
setcallback!(s::SimWrapper, cb) = s.callback = cb

function update!(sim, wrapper :: SimWrapper)
    update!(unwrap(wrapper))
    schedule!(sim, callback(wrapper), clockperiod(unwrap(wrapper)))
    wrapper.visits += 1
    return nothing
end

function wrap!(sim, obj :: T) where T
    wrapper = SimWrapper(obj)
    callback = Callback(sim -> update!(sim, wrapper))
    setcallback!(wrapper, callback)

    return wrapper
end

LightDES.schedule!(sim::Simulation, wrapper::SimWrapper) = schedule!(sim, callback(wrapper), 0)
