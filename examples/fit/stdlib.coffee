simport Sunny.Dsl
simport Sunny.Fun
simport Sunny.Types

# ============================ EVENTS ======================================

event class Create extends SunnyClientEvent
  params:
    kls: Klass
    params: Obj

  requires: () ->
    return "must specify klass" if not this.kls
    
  ensures: () ->
    this.kls.create(params)


event class Destroy extends SunnyClientEvent
  params:
    obj: Record

  requires: () ->
    return "must specify object" if not this.obj
    
  ensures: () ->
    this.obj.destroy()
