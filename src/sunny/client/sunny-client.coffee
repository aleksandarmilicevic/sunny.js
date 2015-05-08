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
                 d = new jQuery.Deferred()
                 sigName = $elem.attr("sunny-sig")
                 sig = Sunny.Meta.findSig sigName
                 return d.reject("sig #{sigName} not found") unless sig
  
                 obj = sig.findOne(params.pk)
                 return d.reject("object does not exist any more") unless obj
  
                 obj[params.name] = params.value
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

    
    Router.route "/uiGeneratorLists", -> @render "uiGeneratorLists"
    Router.route "/uiGeneratorForms", -> @render "uiGeneratorForms"
    Router.route "/database", -> @render "Spreadsheet"  # @deprecated (should show list of avail sheets)
    Router.route "/database/:sheet", ->
      @render "Spreadsheet", data: {sheet: @params.sheet}
    Router.route "/database/:sheet/views/:_id", ->
      @render "Spreadsheet", data: {sheet: @params.sheet, viewId: @params._id}
    Router.route "/database/:sheet/schema", ->
      @render "Schema", data: {sheet: @param.sheet}
    
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
      $closestEventBlock.find("[sunny-event-param]").each () ->
        pName = $(this).attr("sunny-event-param")
        if pName.indexOf(pfix) == 0
          pName = pName.substring(pfix.length)
          setEventParam(ev, pName, $(this).val(), $(this))
  
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
      else if Sunny.Types.isSigKls(ev.meta().field(pName).type?.domain())
        sigCls = ev.meta().field(pName).type?.domain()
        pVal = sigCls.findById(paramValue)
        
    ev[pName] = pVal

