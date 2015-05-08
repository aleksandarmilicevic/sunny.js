@createFormsTabs = ->
  sunnyEvents = Object.keys(Sunny.Meta.events)
  sunnyEvents = sunnyEvents.filter (val) -> val not in ["Destroy", "ClientEvent"]
  tabContainer = $("#tabs")
  tabContent = $("#tabContent")
  tabCode = ""
  contentCode = ""
  for sunnyEvent, i in sunnyEvents
    active = ""
    if i == 0
      active = " active"
    tabCode = "<li class='"+active+"'><a href='#"+sunnyEvent+"Events"+"' data-toggle='tab'>"+sunnyEvent+"</a></li>"
    tabContainer.append(tabCode)
    params = Sunny.Meta.events[sunnyEvent].__meta__.fields
    contentCode = "<div class='tab-pane"+active+"' id='"+sunnyEvent+"Events'> <div class='attributeList'> <form id='"+sunnyEvent+"Form' name='"+sunnyEvent+"Form' class='inlineB' action='' method='GET'>"
    for param in params
      if param.type.isPrimitive() == true
        contentCode += "<div> <input type='checkbox' class='param'  name='"+param.name+"' value='"+param.name+"'>"+param.name+" </div>"
      else if param.type.isReference() == true 
        contentCode += "<span> For "+param.name+" </span> <br>"
        subFields = Sunny.Meta.records[param.type.klasses[0].name].__meta__.fields
        for subField in subFields
          if subField.type.isPrimitive() == true
            contentCode += "<div> <input type='radio' class='refParam'  data-param='"+param.type.klasses[0].name+"' name='"+param.name+"' value='"+subField.name+"'> "+param.name+"-"+subField.name+" </div>"
    
    contentCode += "<button onClick='return formsView(this.form);'>Generate Template</button> <br> <button onClick='return generateFormsViewSunnyCode(this.form);'>Generate Code</button></form><div class='formView formView"+sunnyEvent+" inlineB'>Preview</div></div></div>"
    tabContent.append(contentCode)


@createListViewTabs = ->
  models = Object.keys(Sunny.Meta.records)
  tabContainer = $("#tabs")
  tabContent = $("#tabContent")
  tabCode = ""
  contentCode = ""
  for model, i in models
    active = ""
    if i == 0
      active = " active"
    tabCode = "<li class='"+active+"'><a href='#"+model+"Attributes"+"' data-toggle='tab'>"+model+"</a></li>"
    tabContainer.append(tabCode)
    fields = Sunny.Meta.records[model].__meta__.allFields()
    contentCode = "<div class='tab-pane"+active+"' id='"+model+"Attributes'> <div class='attributeList'> <form id='"+model+"Form' name='"+model+"Form' class='inlineB' action='' method='GET'>"
    for field in fields
      if field.name != "_mUser"
        if field.type.isPrimitive() == true
          contentCode += "<div> <input type='checkbox' class='field'  name='"+field.name+"' value='"+field.name+"'>"+field.name+" </div>"
        else if field.type.isReference() == true 
          contentCode += "<span> For "+field.name+" </span> <br>"
          subFields = Sunny.Meta.records[field.type.klasses[0].name].__meta__.allFields()
          for subField in subFields
            if subField.type.isPrimitive() == true
              contentCode += "<div><input type='checkbox' class='subField'  data-model='"+field.name+"' name='"+subField.name+"' value='"+subField.name+"'> "+field.name+"-"+subField.name+"</div>"
          

    contentCode += "<button onClick='return listView(this.form);'>Generate Template</button> <br> <button onClick='return generateListViewSunnyCode(this.form);'>Generate Code</button></form><div class='formView listView"+model+" inlineB'>Preview</div></div></div>"
    tabContent.append(contentCode)

@formsView = (form) ->
  console.log("form views")
  sunnyEvent=$(form).attr("id").replace("Form", "")
  params = []
  refParams = {}
  for input in $(form).find('.param:checked')
    params.push($(input).val())
  for input in $(form).find('.refParam:checked')
    if refParams[$(input).attr("data-param")]
      refParams[$(input).attr("data-param")].push([$(input).attr("name"),$(input).val()])
    else
      refParams[$(input).attr("data-param")] = [$(input).attr("name"),$(input).val()]
  paramsObj = Sunny.Meta.events[sunnyEvent].__meta__.fields
  formCode = "<div><h4>"+sunnyEvent+" Event</h4>"
  formCode += "<div class='"+sunnyEvent+"Form form-inline' onkeypress='return event.keyCode != 13;' sunny-event-name='"+sunnyEvent+"' >  <div class='form-group'>"
  for param in params
    formCode += "<div> "+param+":<input type='text' name='"+param+"' placeholder='Enter Text' sunny-event-param='"+sunnyEvent+"."+param+"'/> </div>"

  for refParam in Object.keys(refParams)
    formCode += "<div> Select "+refParams[refParam][0]+": <br> <select name="+refParams[refParam][0]+" sunny-event-param='"+sunnyEvent+"."+refParams[refParam][0]+"'> "
    for obj in Sunny.Meta.records[refParam].all()
      formCode += "<option value='"+obj.id()+"'>"+obj[refParams[refParam][1]]+"</option> "
    formCode += "</select> </div>"

  formCode += "<button class='btn btn-default "+sunnyEvent+"' sunny-trigger='--closest--'> "+sunnyEvent+" </button> </div>"
  listViewContainer = $(".formView"+sunnyEvent)
  listViewContainer.html(formCode)
  return false

@listView = (form) ->
  console.log("List View")
  model=$(form).attr("id").replace("Form", "")
  attributes = []
  subAttributes = {}
  for input in $(form).find('.field:checked')
    attributes.push($(input).val())
  for input in $(form).find('.subField:checked')
    if subAttributes[$(input).attr("data-model")]
      subAttributes[$(input).attr("data-model")].push($(input).val())
    else
      subAttributes[$(input).attr("data-model")] = [$(input).val()]
  objects = Sunny.Meta.records[model].all()
  listCode = "<div><h4>"+model+" List</h4>"

  for obj in objects
    listCode += '<div class="listObject"><span class="floatR btn btn-default btn-sm my-icon-btn glyphicon glyphicon-remove" sunny-event-name="Destroy" sunny-param-obj="$<Sunny.Meta.records["'+model+'"].new({_id: "'+obj.id()+'"})> </span>'
    for attr in attributes
      if typeof obj[attr] == "string"
        listCode +="<div> "+attr+": "+"<span sunny-editable-fld='true' sunny-sig='"+model+"' sunny-atom-id='"+obj.id()+"' sunny-fld-name='"+attr+"' class='editable editable-click'>"+obj[attr]+"</span></div>"
      else if obj[attr] instanceof Array
        for subObj in obj[attr]
          listCode += "<div> "+attr+": "+"<span>"+subObj+"</span></div>"
    for subAttr in Object.keys(subAttributes)
      listCode += "<div class='subObject'>"  
      if obj[subAttr] instanceof Array
        subModel = obj[subAttr][0].type()
        for subObj in obj[subAttr]
          for subSubAttr in subAttributes[subAttr]
            listCode +="<div>"+subAttr+"-"+subSubAttr+": " +"<span sunny-editable-fld='true' sunny-sig='"+subModel+"' sunny-atom-id='"+subObj.id()+"' sunny-fld-name='"+subSubAttr+"' class='editable editable-click'>"+subObj[subSubAttr]+"</span></div>"
      else 
        subModel = obj[subAttr].type()
        for subSubAttr in subAttributes[subAttr]
          listCode +="<div> "+subAttr+"-"+subSubAttr+": "+"<span sunny-editable-fld='true' sunny-sig='"+subModel+"' sunny-atom-id='"+obj[subAttr].id()+"' sunny-fld-name='"+subSubAttr+"' class='editable editable-click'>"+obj[subAttr][subSubAttr]+"</span></div>"
      listCode += "</div>"

    listCode += "</div>"

  listCode += "</div>"
  listViewContainer = $(".listView"+model)
  listViewContainer.html(listCode)
    
  
  
  return false

@generateFormsViewSunnyCode = (form) ->
  console.log("form views")
  sunnyEvent=$(form).attr("id").replace("Form", "")
  sunnyCodeContainer = $("#sunnyCodeContainer")
  params = []
  refParams = {}
  for input in $(form).find('.param:checked')
    params.push($(input).val())
  for input in $(form).find('.refParam:checked')
    if refParams[$(input).attr("data-param")]
      refParams[$(input).attr("data-param")].push([$(input).attr("name"),$(input).val()])
    else
      refParams[$(input).attr("data-param")] = [$(input).attr("name"),$(input).val()]
  paramsObj = Sunny.Meta.events[sunnyEvent].__meta__.fields
  formCode = "<div><h4>"+sunnyEvent+" List</h4> \n\ "
  formCode += "<div {{"+sunnyEvent+" }} class='"+sunnyEvent+"Form formView form-inline' onkeypress='return event.keyCode != 13;'> \n\ <div class='form-group'> \n\ "
  for param in params
    formCode += " "+param+":<input type='text' name='"+param+"' placeholder='Enter Text' {{"+sunnyEvent+"_"+param+"}}/> \n\ "

  for refParam in Object.keys(refParams)
    formCode += "Select "+refParams[refParam][0]+": <br> <select name='"+refParams[refParam][0]+"' {{"+sunnyEvent+"_"+refParams[refParam][0]+"}}> \n\ "
    formCode += "{{#each "+refParam+"}} \n\ "
    formCode += "<option value='{{this.__props__._id}}'>{{this."+refParams[refParam][1]+"}}</option> \n\ "
    formCode += "{{/each}} \n\ </select> \n\ "

  formCode += "<button class='btn btn-default "+sunnyEvent+"' {{sunny_trigger}}> "+sunnyEvent+" </button> \n\ </div> \n\ </div> \n\ </div>"

  sunnyCodeContainer[0].innerHTML = '<pre>' + formCode.replace(/&/g, '&amp;').replace(/</g, '&lt;') + '</pre>'
  console.log("generate code")
  return false

@generateListViewSunnyCode = (form) ->
  model=$(form).attr("id").replace("Form", "")
  fields = Sunny.Meta.records[model].__meta__.allFields()
  fieldsDic = {}
  for field in fields
    if field.name != "_mUser"
      fieldsDic[field.name] = field
  attributes = []
  subAttributes = {}
  sunnyCodeContainer = $("#sunnyCodeContainer")
  for input in $(form).find('.field:checked')
    attributes.push($(input).val())
  for input in $(form).find('.subField:checked')
    if subAttributes[$(input).attr("data-model")]
      subAttributes[$(input).attr("data-model")].push($(input).val())
    else
      subAttributes[$(input).attr("data-model")] = [$(input).val()]
  sunnyCode = "<div><h4>"+model+" List</h4> \n\ "
  sunnyCode += "<div > \n\ {{#each "+model+"}} \n\ <div class='listObject'><span class='"+model+"-exit pull-right btn btn-default btn-sm my-icon-btn glyphicon glyphicon-remove' {{sunny_trigger event='Destroy' obj=this}}> </span> \n\ "
  for attr in attributes
    if fieldsDic[attr].type.isPrimitive() == true and fieldsDic[attr].type.isComposition() == false
      sunnyCode +="<div class='"+model+"-"+attr+"' > <div>"+attr+" :<span {{editableField obj=this fld='"+attr+"'}}> {{this."+attr+"}}</span></div></div> <hr> \n\ " 
    else if fieldsDic[attr].type.isPrimitive() == true
      sunnyCode +="<div class='"+model+"-"+attr+"' ><div>"+attr+" : "+"<span>{{this."+attr+"}}</span></div></div> <hr> \n\ " 
  for subAttr in Object.keys(subAttributes)
    sunnyCode += "<div class ='subObject'>"
    if fieldsDic[subAttr].type.isReference() == true and fieldsDic[subAttr].type.isComposition() == false
      for subSubAttr in subAttributes[subAttr]
        sunnyCode +="<div class='"+model+"-"+subAttr+"-"+subSubAttr+"' ><div>"+subAttr+"-"+subSubAttr+" :<span {{editableField obj=this fld='"+subSubAttr+"'}}> {{this."+subAttr+"."+subSubAttr+"}}</span></div></div> <hr> \n\ " 
    else if fieldsDic[subAttr].type.isReference() == true and fieldsDic[subAttr].type.isComposition() == true
        sunnyCode += "{{#each this."+subAttr+"}} \n\ "
        for subSubAttr in subAttributes[subAttr]
          sunnyCode +="<div class='"+model+"-"+subAttr+"-"+subSubAttr+"' ><div>"+subAttr+"-"+subSubAttr+"<span {{editableField obj=this fld='"+subSubAttr+"'}}> : {{this."+subSubAttr+"}}</span></div></div> <hr> \n\ " 
        sunnyCode += "{{/each}}"
    sunnyCode += "</div>"
  sunnyCode += "</div>{{/each}} \n\ </div>"
  sunnyCodeContainer[0].innerHTML = '<pre>' + sunnyCode.replace(/&/g, '&amp;').replace(/</g, '&lt;') + '</pre>'
  console.log("generate code")

  return false

@list_ready = ->
  createListViewTabs()
  $('#tabs').tab()
  

@forms_ready = ->
  createFormsTabs()
  $('#tabs').tab()



