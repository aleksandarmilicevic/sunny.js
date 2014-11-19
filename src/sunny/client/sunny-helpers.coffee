if Meteor.isClient
    
    UI.registerHelper "Client", () -> Sunny.myClient()
    UI.registerHelper "Server", () -> Sunny.myServer()
    UI.registerHelper "onlineClients", () -> Sunny.myServer()?.onlineClients

    UI.registerHelper "isMe", (user) ->
      return user?.id() == Sunny.myClient()?.user?.id()

    UI.registerHelper "editableField", (kw) ->
      return {} unless kw
      obj = kw.hash.obj
      fldName = kw.hash.fld
      return {} unless obj
      "sunny-editable-fld" : true
      "sunny-sig"          : obj.type()
      "sunny-atom-id"      : obj.id()
      "sunny-fld-name"     : fldName
      "class"              : "editable editable-click"

    UI.registerHelper "sunny_event_param", (ctx) ->
      ans = {}
      return ans

    UI.registerHelper "sunny_trigger", (ctx) ->
      evName = switch
        when not ctx                     then "--closest--"
        when typeof(ctx) == "string"     then ctx
        when Sunny.Types.isEventKls(ctx) then ctx.name
        else null
      return "sunny-trigger": evName if evName    
      if ctx.hash
        ans = _eventMeta(ctx)
        ans["sunny-trigger"] = "--closest--"
        return ans
      else
        return {}

    UI.registerHelper "dbg", (x) -> console.log x

    _eventMeta = (kw) ->    
      return {} unless kw?.hash
      kw = kw.hash
      ans = {}
      if typeof(kw.event) == "string"
        ans["sunny-event-name"] = kw.event
      else if Sunny.Types.isSubklass(kw.event, Sunny.Model.Event)
        ans["sunny-event-name"] = kw.event.name
      else if kw.event instanceof Sunny.Model.Event
        ev = kw.event
        ans["sunny-event-name"] = ev.meta().name
        for pn in ev.meta().allParams()
          if ev[pn]
            _addEventParamValue(ans, pn, ev[pn])
        
      for pn, pv of kw
        if pn != "event"
          _addEventParamValue(ans, pn, pv)
      return ans

    UI.registerHelper "sunny_eventMeta", _eventMeta

    _addEventParamValue = (hash, paramName, paramValue) ->
      pname = "sunny-param-#{paramName}"
      pvalue = paramValue
      if typeof(pvalue._inspect) == "function"
        pvalue = "$<#{pvalue._inspect()}>"
      hash[pname] = pvalue
      
