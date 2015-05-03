if Meteor.isClient
  Meteor.startup () ->
    $(document).on "click", "[sunny-editable-fld='true']", (elem) ->
      $elem = $(this)
      $elem.editable
        type:  "text"
        name:  $elem.attr("sunny-fld-name")
        pk:    $elem.attr("sunny-atom-id")
        value: ""
        placement: "bottom"
        display: false
        url:   (params) ->
                 $e = $(this)
                 d = new jQuery.Deferred()
                 sigName = $elem.attr("sunny-sig")
                 sig = Sunny.Meta.findSig sigName
                 return d.reject("sig #{sigName} not found") unless sig
  
                 obj = sig.findOne($e.attr("sunny-atom-id"))
                 return d.reject("object does not exist any more") unless obj
  
                 obj[$e.attr("sunny-fld-name")] = params.value
                 writeOutcome = Sunny.ACL.lastWriteOutcome()
                 if writeOutcome?.isDenied()
                   return d.reject(writeOutcome.denyReason || "not allowed")
                 else
                   return d.resolve()
      $elem.editable 'show'
  
    $(document).on "click", "[sunny-trigger]", (elem) ->
      if this.tagName != "INPUT" || this.type == "checkbox"
        triggerEvent($(this))
  
    $(document).on "keypress", "input[sunny-trigger]", (e) ->
      if e.keyCode == 13
        triggerEvent($(this))
        $(this).val("")
  
  triggerEvent = ($elem) ->
    $closestEventBlock = null
    evKlsName = $elem.attr("sunny-trigger")
    if evKlsName == "--closest--"
      $closestEventBlock = $elem.closest("[sunny-event-name]")
      evKlsName = $closestEventBlock.attr("sunny-event-name")
    eventKls = Sunny.Meta.events[evKlsName]
    return unless eventKls
    ev = eventKls.new()
  
    if not $closestEventBlock
      sel = "[sunny-event-name='#{eventKls.name}']"
      $closestEventBlock = $elem.closest(sel)
    if $closestEventBlock.length > 0
      iterParamAttributes $closestEventBlock[0].attributes, (an, av) ->
        setEventParam(ev, an, av, $closestEventBlock)
      pfix = "#{eventKls.name}."
      parseAndSetEventParam = ($e) ->
        pName = $e.attr("sunny-event-param")
        if pName && pName.indexOf(pfix) == 0
          pName = pName.substring(pfix.length)
          setEventParam(ev, pName, $e.val(), $e)
      $closestEventBlock.find("[sunny-event-param]").each () -> parseAndSetEventParam($(this))
      parseAndSetEventParam($closestEventBlock)  

    unless $elem.get(0) == $closestEventBlock[0]
      iterParamAttributes $elem.get(0).attributes, (an, av) ->
        setEventParam(ev, an, av, $elem)
  
    ev.trigger()
  
  iterParamAttributes = (attrs, cb) ->
    for attr in attrs
      if attr.name.indexOf("sunny-param-") == 0
        pName = attr.name.substring("sunny-param-".length)
        cb.call(null, pName, attr.value)
  
  setEventParam = (ev, paramName, paramValue, $elem) ->
    evParams = ev.meta().allParams()
    pNameIdx = evParams.findIndex (s) -> s.toLowerCase() == paramName.toLowerCase()
    return if pNameIdx == -1
    pName = evParams[pNameIdx]
    pVal = paramValue
    if typeof(paramValue) == "string"
      if paramValue.indexOf("$<") == 0 && paramValue[paramValue.length - 1] == ">"
        jsCode = paramValue.substring(2, paramValue.length-1)
        fn = eval "function f() { return #{jsCode}; }; f"
        pVal = fn.call($elem)
      else if Sunny.Types.isSigKls(ev.meta().field("room").type?.domain())
        sigCls = ev.meta().field("room").type?.domain()
        pVal = sigCls.new({id: paramValue})
        
    ev[pName] = pVal

