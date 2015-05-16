@loadSampleData = (model) ->
  # Sample schema and data in a more human-friendly hierarchical format.

  records = Object.keys(Sunny.Meta.records)
  type_dic = {Text: "_string", Val: "_string", Int: "_string"}
  testSchema = []
  subClassSchema = []
  objectAttributeMap ={}
  for record in records
    obj = {type: '_token', cellName: record, children: []}
    parent = Sunny.Meta.records[record].__meta__.parentSig.name
    if parent != "Record" and parent != "SunnyUser"
      obj.type = '_unit'
      obj.children.push {name: "parent", type: parent }
    fields = Sunny.Meta.records[record].__meta__.allFields()
    for field in fields
      if field.name != "_mUser"
        
        if field.type.isPrimitive() == true
          fieldObj = {name: field.name, type: type_dic[field.type.klasses[0].name]}

        else if field.type.isReference() == true and field.type.isComposition() == false
          fieldObj = {name: field.name, type: field.type.klasses[0].name, children: [] }

        else if field.type.isComposition() == true
          fieldObj = {name: field.name, type: field.type.klasses[0].name, children: [] }
        obj.children.push fieldObj

    if parent != "Record" and parent != "SunnyUser"
      for doneObj in testSchema
        if doneObj.cellName == parent
          doneObj.children.push obj
          subClassSchema.push obj
    else
      testSchema.push obj
  console.log(JSON.stringify(testSchema))
  # Shorthands:

  # Simple value(s)
  V = () -> ([val, {}] for val in arguments)

  # Type _unit
  U = (cell) -> [['X', cell]]

  # Type _token: successive integer tokens for now.
  T = (cellList) -> ([i.toString(), cell] for cell, i in cellList)

  I = () ->
    for x in arguments
      if typeof x == 'number' then x.toString() else x

  # _mark is used only to refer to a cell within this input format.  IDs will be
  # assigned by the loading code.
  sampleData = {
    ##TODO add data from database
  }

  combinedSchema = testSchema #.concat subClassSchema
  for modelType in combinedSchema
    objects = Sunny.Meta.records[modelType.cellName].all()
    Sunny.DataVisualiser.objectidCellidMap[modelType.cellName] = {}
    Sunny.DataVisualiser.cellidObjectidMap[modelType.cellName] = {}
    attributes = modelType.children
    instancesDone = []
    counter = 0
    for instance in objects
      instanceDone ={}
      for attribute in attributes
        if instance[attribute.name] instanceof Array
          subArray = []
          for ins in instance[attribute.name]
            if attribute.type == "_string"
              subArray.push ins
            else
              referenceId = Sunny.DataVisualiser.objectidCellidMap[ins.type()][ins.id()]
              subArray.push I(referenceId)

            instanceDone[attribute.name] =  V.apply(this,subArray)
        else if attribute.type == "_string"
          instanceDone[attribute.name] = V(instance[attribute.name])
        else if instance[attribute.name]
          referenceId = Sunny.DataVisualiser.objectidCellidMap[attribute.type][instance[attribute.name].id()]
          instanceDone[attribute.name] = V(I(referenceId))
      instancesDone.push instanceDone      
      Sunny.DataVisualiser.objectidCellidMap[modelType.cellName][instance.id()]= counter
      Sunny.DataVisualiser.cellidObjectidMap[modelType.cellName][counter] = instance.id()
      counter = counter+1
    Sunny.DataVisualiser.modelNextId[modelType.cellName] = counter
    sampleData[modelType.cellName] = T(instancesDone)
  # Add a super dict representing _unit, though it doesn't get an ID or anything.
  console.log(sampleData)
  superSchema = {children: testSchema}

  # Delete all existing columns!!
  model.drop()
  Views.remove {}
  console.log "Loading sample data into tablespace '#{$$.id}'"

  scanColumns = (parentId, schema) ->
    schema.children ?= []
    for columnDef, i in schema.children
      thisId = model.defineColumn(
        parentId, i,
        columnDef.name,
        # This only works because all of the types in our sample dataset refer to
        # columns that come earlier in preorder.  We can probably live with this
        # until we implement full validation of acyclic type usage.
        parseTypeStr(columnDef.type),
        columnDef.cellName,
        null  # formula
      )
      scanColumns(thisId, columnDef)
  scanColumns(rootColumnId, superSchema)

  # Insert cells into columns.
  insertCells = (columnId, cellId, cellData) ->
    for childColumnName, childCells of cellData ? {}
      childColumnId = childByName(model.getColumn(columnId), childColumnName)
      childColumn = new ColumnBinRel(childColumnId)
      for entry in childCells  # No point in making a map just to expand it again.
        [value, childCellData] = entry
        childColumn.add(cellId, value)
        insertCells(childColumnId, cellIdChild(cellId, value), childCellData)
  insertCells(rootColumnId, rootCellId, sampleData)

  # Add some formula columns.
  defineParsedFormulaColumn = (parentRef, order, name, cellName, specifiedType, formulaStr, attrs) ->
    # Ludicrously inefficient, but we need the column type fields to be set in
    # order to parse formulas.
    model.typecheckAll()
    parentId = parseColumnRef(parentRef)

    model.defineColumn(parentId,
                       order, name, cellName, specifiedType,
                       parseFormula(parentId, formulaStr), attrs)
  
  model.evaluateAll()  # prepare dependencies

  # Create a view
  T = -> new Tree arguments...

  view1 =
    _id: '1'
    layout: T('_root')
            .map parseColumnRef

  Views.upsert(view1._id, view1)
  Sunny.DataVisualiser.isLoaded = true
  console.log "Loaded sample data into tablespace '#{$$.id}'"
  model
