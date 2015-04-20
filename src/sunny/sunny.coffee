Fiber = Npm.require('fibers')    if Meteor.isServer

# ----------------------------
# global Sunny var
# ----------------------------

`Sunny = {};`
`App = {};`

# ====================================================================================
#   Sunny top-level
# ====================================================================================

Sunny.simport = (context, sunnyPkg) ->
  return Sunny.simportAll(context, sunnyPkg) unless sunnyPkg?.__exports__?
  for name in sunnyPkg.__exports__
    context[name] = sunnyPkg[name]

Sunny.simportAll = (context, sunny_pkg) ->
  for name, value of sunny_pkg
    context[name] = value

Sunny.myServer = () ->
  return Sunny.Meta.serverKls().findOne({}) # has to be only one
  # if Sunny._myServer
  #   return Sunny._myServer
  # else
  #   Sunny._myServer = Sunny.Meta.serverKls().findOne({}) # has to be only one
  #   return Sunny._myServer

Sunny.myClient = () ->
  if Meteor.isServer
    return Sunny._currClient.get()
  else if not Sunny.myServer()
    return null
  else if not Meteor.status().connected or not Meteor.connection
    return null
  else
    connId = Meteor.connection._lastSessionId
    myClient = Sunny.Meta.clientKls().findOne("_mConn.id": connId);
    return myClient

Sunny.currClient = Sunny.myClient

Sunny.methods = (hash) ->
  mthds = {}
  for name, fn of hash
    do(name, fn) ->
      wfn = fn
      if (Meteor.isServer)
        wfn = Sunny.Queue.wrapAsInvocation "M-#{name}", fn
      mthds[name] = wfn
  Meteor.methods mthds

# ====================================================================================
#   Globally exported functions
# ====================================================================================

`simport = function(sunny_pkg) { Sunny.simport(this, sunny_pkg); };`

# ====================================================================================
#   Functional-style functions over arrays
# ====================================================================================

Sunny.Fun = do ->
  groupByKey: (arr, key) ->
    ans = []
    for elem in arr
      k = elem[key]
      e = findFirst ans, (e) -> _equalsFn(e.key)(k)
      if not e
        e = {key: k, value: []}
        ans.push e
      e.value.push(elem)
    return ans
    
  map: (col, cb) ->
    ans = []
    ans.push(cb(e)) for e in col
    return ans

  mapFilter: (col, mapFn, filterFn) ->
    if not filterFn
      filterFn = (e) -> e != null && e != undefined
    ans = []
    for e in col
      val = mapFn(e)
      ans.push(val) if filterFn(val)
    return ans

  fold: (col, init, cb) ->
    acc = init
    for e in col
      acc = cb(e, acc)
    return acc

  findFirst: (col, cb) ->
    for e in col
      return e if cb(e)
    return null

  findLast: (col, cb) ->
    for i in [col.length-1 .. 0]
      e = col[i]
      return e if cb(e)
    return null

  findIndex: (col, cb) ->
    idx = 0
    for e in col
      return idx if cb(e)
      idx = idx + 1
    return -1

  contains: (col, targetElem) ->
    findIndex(col, _equalsFn(targetElem)) != -1

  filter: (col, cb) ->
    ans = []
    for e in col
      ans.push e if cb(e)
    return ans

  all: (col, cb) ->
    for e in col
      return false if not cb(e)
    return true
    
  some: (col, cb) ->
    for e in col
      return true if cb(e)
    return false

Sunny.simportAll(this, Sunny.Fun)

# ====================================================================================
#   Configuration
# ====================================================================================

Sunny.Conf = do ->
  registerGlobalNames: true
  serverRecordPersistence: "reuse" # valid values: 'reuse', 'create', 'replace'

# ====================================================================================
#   standard prototype extensions
# ====================================================================================

Array.prototype.map  = (cb)             -> map this, cb
Array.prototype.find = (cb)             -> findFirst this, cb
Array.prototype.contains = (targetElem) -> contains this, targetElem
Array.prototype.groupByDomain = ()      -> groupByKey(this, 0)
Array.prototype.groupByRange = ()       -> groupByKey(this, 1) #TODO: use last index instead of 1
Array.prototype.findIndex = (cb) ->
  idx = 0
  for e in this
    return idx if cb(e)
    idx = idx + 1
  return -1

# ====================================================================================
#   private
# ====================================================================================

applyDbOp = (fnName, obj, args...) ->
  fn = obj[fnName]
  # if Meteor.isServer && Sunny.Queue.currInvocation()
  #   sdebug "in invocation"
  #   args.push {tx: true}
  return fn.apply(obj, args)

getSunnyClient = (conn) ->
  if conn instanceof SunnyClient
    conn
  else
    Sunny.Meta.clientKls().findOne({"_mConn.id": conn})

onBehalf = (fn, clnt) ->
  old = Sunny._currClient.get()
  try
    Sunny._currClient.set(clnt)
    fn.apply(null)
  finally
    Sunny._currClient.set(old)

onClientBehalf = (conn, fn) ->
  if not conn
    return fn.apply(null)
  else
    return onBehalf(fn, getSunnyClient(conn))

onServerBehalf = (fn) -> onBehalf(fn, null)

fixKlsParent = (kls, parent) ->
  console.log "class #{kls.name} < #{parent?.name}"
  sig = kls
  parentSig = kls.__super__?.constructor || parent
  unless kls.__super__?
    oldProt = kls.prototype
    `__extends(sig, parent)` # this changes sig.prototype (sets it to a different value)
    sig.prototype[pn] = p for pn, p of oldProt
  return [sig, parentSig]

updateParentsSubsigs = (sig, parentSig) ->
  ps = parentSig
  while ps
    ps.__meta__.subsigs.push(sig)
    ps = ps.__meta__.parentSig

extractFieldEntries = (map) ->
  ans = []
  for pn, p of map
    if pn == "constructor" # skip the constructor function
    else
      type = Sunny.Types.asType(p)
      if type
        ans.push new Field(pn, type)
  return ans

defineFldProperty = (sig, fldName, propName) ->
  propName = fldName unless propName
  gfun = "function _get_#{propName}(o)   { return this.readField('#{fldName}', o); };
          _get_#{propName};"
  sfun = "function _set_#{propName}(v, o){ return this.writeField('#{fldName}', v, o); };
          _set_#{propName};"
  Object.defineProperty(sig.prototype, propName, {
    enumerable: true
    get: eval(gfun)
    set: eval(sfun)
  })

addFieldsAndMethods = (sig, parentSig) ->
  # add fields
  for f in extractFieldEntries(sig.prototype)
    if not parentSig.__meta__.hasField(f.name)
      sig.__meta__.addField(f)
   for fld in sig.__meta__.allFields()
    defineFldProperty sig, fld.name

addStaticMethods = (sig) ->
  sig.__meta__.staticBlock = sig.prototype.__static__
  delete sig.prototype.__static__ if sig.__meta__.staticBlock

  s = sig
  while s && s.__meta__
    for pn, pv of s.__meta__.staticBlock
      pv = pv.bind(sig) if typeof(pv) == "function"
      sig[pn] = pv
    s = s.__meta__.parentSig

registerKW = (key, val) ->
  Sunny.Utils.safeReg(window, key, val) if Meteor.isClient && Sunny.Conf.registerGlobalNames
  App[key] = val

register = (kls) -> registerKW(kls.name, kls)

toMeteorRef = (obj) ->
  if obj instanceof Array
    map obj, toMeteorRef
  else if typeof(obj?._toMeteorRef) == "function"
    obj._toMeteorRef()
  else
    obj


_equalsFn = (obj) ->
  if !obj
    return (e) -> !e
  if obj && Sunny.Types.isSigKls(obj.constructor) # && not this._myFld.type.isPrimitive() &&
    return (e) -> obj.equals(e)
  if obj && obj instanceof Sunny.Model.Op
    return (e) -> obj.equals(e)
  if obj instanceof Array
    return (arr) ->
      return false unless arr instanceof Array
      return false unless arr.length == obj.length
      idx = 0
      for e in obj
        return false unless _equalsFn(e)(arr[idx])
        idx = idx + 1
      return true        
  return (e) -> obj == e

_objToArray = (obj) ->
  ans = []
  for p, v of obj
    ans.push {key: p, value: v}
  return ans

_cleanupClient = (client, connId) ->
  connId ?= client?._mConn?.id
  for sig in Sunny.Meta.recordsAndMachines
    sig.__meta__._cleanupConn(connId)

# ====================================================================================
#   Sunny.Utils
# ====================================================================================

Sunny.Utils = do ->
  class FiberLocalVar
    constructor: (name, val) ->
      @name = name
      @__sunny_locals = {}
      @defVal = val
      this.set(val)
    get:         (defVal)    -> this._storage()[@name] || defVal || @defVal
    set:         (val)       -> this._storage()[@name] = val; val

    # array functions
    push:        (val)       -> arr = this.get([]); arr.push val; this.set(arr)
    pop:         ()          -> arr = this.get([]); ans = arr.pop(); this.set(arr); return ans
    peek:        ()          -> arr = this.get([]); if arr.length == 0 then undefined else arr[arr.length-1]
    getAt:       (idx)       -> arr = this.get([]); if arr.length <= idx then undefined else arr[idx]

    _storage: () ->
      if Meteor.isServer and fc = Fiber.current
        fc.__sunny_locals ?= {}
      else
        @__sunny_locals

  fiberIdCnt = 0
  fiberIdVar = new FiberLocalVar("Sunny.fiberId")

  toSig: (sig) ->
    switch
      when typeof(sig) == "string"   then Sunny.Meta.findSig(sig)
      when Sunny.Types.isSigKls(sig) then sig
      else sthrow("not a sig: #{sig} (#{typeof(sig)})")

  toObj: (obj) ->
    switch
      when obj instanceof Sig then obj
      when o = convertObj(null, obj) then o
      else sthrow("not a Sunny object")

  ensureFld: (obj, fname) ->
    fld = obj.meta().field(fname)
    sthrow("field '#{fldName}' not found in '#{meta.name}'") unless fld
    fld

  assert: (b, msg) ->
    if not b
      msg ?= "<no message>"
      Sunny.Log.sfatal "assertion failed: #{msg}"

  FiberLocalVar: FiberLocalVar
  fiberId:       () ->
    id = fiberIdVar.get()
    id = fiberIdVar.set(fiberIdCnt++) unless id
    id

  safeReg: (obj, key, val) ->
    obj[key] = val unless obj.hasOwnProperty(key)

assert = Sunny.Utils.assert

# ====================================================================================
#   Sunny.Log
# ====================================================================================

Sunny.Log = do ->
  _tab = "  "
  _styles = [(x) -> x]
  _bgstyles = [(x) -> x]
  _errStyle = (x) -> x
  _connIdIdx = {}
  _connIdxCnt = 0
  _indent = new Sunny.Utils.FiberLocalVar("Sunny.Log.indent", "")

  if Meteor.isServer
    try
      clc = Npm.require('cli-color')
      _styles = [clc.red, clc.green, clc.yellow, clc.cyanBright, clc.magenta]
      _bgstyles = [clc.bgBlackBright, clc.bgGreen, clc.bgBlue, clc.bgCyan, clc.bgMagenta]
      _errStyle = clc.red.bold.bgYellowBright

  _colorFiber = (msg) ->
    idx = Sunny.Utils.fiberId()
    fiberIdTxt = _bgstyles[idx % _bgstyles.length](" (#{idx}) ")
    connId = Sunny._currConnId.get() || 0
    connIdx = _connIdIdx[connId] ?= _connIdxCnt++
    msgTxt = _styles[connIdx % _styles.length](_indent.get("") + msg)
    console.log(fiberIdTxt + msgTxt)

  indent: (fn) ->
    try
      old = _indent.get("")
      _indent.set(old + _tab)
      fn()
    finally
      _indent.set(old)

  slog: (msg) -> console.log(msg)

  srv_sdebug: (msg) ->
    sdebug(msg) if Meteor.isServer

  poly_sdebug: (msg) -> srv_sdebug(msg)    
        
  sdebug: (msg) ->
    return console.log(_indent.get("") + msg) if Meteor.isClient
    _colorFiber(msg)

  strace: (msg) ->
    sdebug(msg)
    console.trace()

  swarn: (msg, level) ->
    return console.log(msg) if Meteor.isClient
    level ?= "WARN"
    console.log(_errStyle("[#{level}] #{msg}"))

  serror: (msg, level) ->
    swarn(msg, level || "ERROR")
    console.trace()

  sthrow: (msg) ->
    serror(msg)
    throw(msg)

  sfatal: (msg) ->
    serror(msg, "FATAL")
    throw(msg)
    # TODO: stop server?


Sunny.simportAll(this, Sunny.Log)

# ====================================================================================
#   Sunny.Deps
# ====================================================================================

Sunny.Deps = do ->
  _compId = 0
  _depId = 0
  _currComp = new Sunny.Utils.FiberLocalVar("Sunny.Deps.currComp")

  # -----------------------------------------------------------------
  #   class Comp
  # -----------------------------------------------------------------
  class Comp
    constructor: (fn) ->
      @_id = String(_compId++)
      @_deps = []
      @fn = fn
      @firstRun = true
      @stopped = false
      @invalidated = false

    invalidate:  () -> return if @invalidated; @invalidated = true; Sunny.Deps.rerun(this) #Sunny.Queue.enqueueComp(this)
    stop:        () -> @stopped = true; @_deps = []; console.log "stoped #{this}"
    hasDeps:     () -> @_deps.length > 0
    run:         () ->
      return if @stopped and not @invalidated
      ans = @fn.call(null, this)
      @firstRun = false
      @invalidated = false
      ans

    printDeps:        (sep) -> map(@_deps, (d) -> d.toString()).join(sep || "\n")
    printEachDepWith: (fn)  -> map @_deps, (d) -> fn(d.toString())
    toString:         ()    -> "Comp(#{@_id})"

    _addDep: (d) -> @_deps.push d

  class CustomComp extends Comp
    constructor: (@connId) ->
      self = this
      runFn = () -> self.exe()
      super(runFn)

    invalidate: () ->
      return if @invalidated
      @invalidated = true
      this.run()

    _exe: (meta, fn) ->
      try
        pub = meta.__pubs__[@connId] || throw("NO_PUB")
        clnt = getSunnyClient(@connId) || throw("NO_CLNT")
        fn.bind(this)(pub, clnt)
      catch err
        this.stop()
        switch err
          when "GHOST"   then swarn "#{@record} not found"
          when "NO_PUB"  then swarn "no publisher for connection #{@connId}"
          when "NO_CLNT" then swarn "client for connection #{@connId} gone"
          else throw(err)


  class FldComp extends CustomComp
    # @param connId [String]
    # @param record [Record]
    # @param fld [Field]
    constructor: (@connId, @record, @fld) ->
      super(connId)

    toString: () -> "FldComp(#{@_id}): #{@record}.#{@fld.name} for conn #{@connId}"

    exe: (fldVal) ->
      meta = @record.meta()
      this._exe meta, (pub, clnt) ->
        fldName = @fld.name
        obj = @record

        fldVal = this._readField() #if fldVal == undefined
        val = wrap(obj, @fld, fldVal)
        check = Sunny.Deps.withComp this, () ->
          onClientBehalf clnt, () ->
            Sunny.ACL.check_read(obj, fldName, val)
        ans = check.returnResult(val, @fld.type?.defaultValue())

        fflds = {}; fflds[fldName] = toMeteorRef(ans)
        pub.sunny_changed meta.name, obj.id(), fflds

    _readField: () ->
      proj = {}; proj[@fld.name] = 1
      dbObj = @record._raw(proj)
      throw("GHOST") if not dbObj
      dbObj[@fld.name]

  class FindComp extends CustomComp
    # @param connId [String]
    # @param sig [Function] (Record type)
    constructor: (@connId, @sig) ->
      super(connId)

    toString: () -> "FindComp(#{@_id}): #{@sig.name} for conn #{@connId}"

    addRecords: (records) ->
      meta = @sig.__meta__
      sig = @sig
      this._exe meta, (pub, clnt) ->
        check = Sunny.Deps.withComp this, () ->
          onClientBehalf clnt, () ->
            Sunny.ACL.check_find(sig, records)
        result = check.returnResult(records, [])
        for r in result
          pub.sunny_added @sig.name, r.id(), {}
          r._serFieldsForClient(@connId)

    setRecords: (records) ->
      meta = @sig.__meta__
      sig = @sig
      this._exe meta, (pub, clnt) ->
        records = @sig.all() if records == undefined
        check = Sunny.Deps.withComp this, () ->
          onClientBehalf clnt, () ->
            Sunny.ACL.check_find(sig, records)
        result = check.returnResult(records, [])

        currentObjs = meta._getPubObjs(@connId)
        diffAdd = []
        diffRem = {}
        diffRem[id] = id for id, id of currentObjs
        for r in result
          if not currentObjs[r.id()]
            diffAdd.push r
          else
            delete diffRem[r.id()]

        for rId in Object.keys(diffRem)
          swarn "removing prev obj: #{@sig.name}(#{rId}) for conn #{@connId}"
          pub.sunny_removed @sig.name, rId

        for r in diffAdd
          pub.sunny_added @sig.name, r.id(), {}
          r._serFieldsForClient(@connId)

    exe: () -> this.setRecords()

  # -----------------------------------------------------------------
  #   class Dep
  # -----------------------------------------------------------------
  class Dep
    constructor: (name) ->
      @_id = String(_depId++)
      @name = name
      @comps = {}

    depend:        () -> this._addComp(Sunny.Deps.currentComp())
    changed:       () ->
      sdebug "#{this} changed; invalidating #{this.numDependents()} comps";
      tmp = @comps
      @comps = {}
      c.invalidate() for cId, c of tmp
    numDependents: () -> Object.keys(@comps).length
    hasDependents: () -> this.numDependents() > 0
    toString:      () -> "Dep(#{@_id})[#{@name}]"

    _addComp: (c) ->
      return unless c
      if not @comps.hasOwnProperty(c._id)
        @comps[c._id] = c
        c._addDep(this)

  _withComp = (comp, blockFn) ->
    if cc = _currComp.get()
      sfatal "tried to nest '#{comp}' under '#{cc}'" if cc != comp
    old = cc
    _currComp.set(comp)
    try
      if blockFn
        blockFn()
      else
        comp.run()
    finally
      _currComp.set(old)

  _run = (comp, fn) -> _withComp(comp || new Comp(fn))

    # sfatal("Nesting autoruns not supported") if cc = _currComp.get()
    # old = cc
    # comp ?= new Comp(fn)
    # _currComp.set(comp)
    # try
    #   comp.run()
    #   comp
    # finally
    #   _currComp.set(old)

  Comp       : Comp
  FldComp    : FldComp
  FindComp   : FindComp
  Dep        : Dep
  currentComp: () -> if Meteor.isClient then null else _currComp.get()
  rerun      : (comp)       -> sdebug("rerunning #{comp}"); _run(comp)
  autorun    : (connId, fn) -> _run(null, fn)
  withComp   : (comp, blockFn) -> _withComp(comp, blockFn)



# ====================================================================================
#   Sunny.Types
# ====================================================================================

Sunny.Types = do ->
  setTypeProperty = (type, propName, propValue) ->
    t = Sunny.Types.asType(type)
    throw("Not a type: #{t}") unless t
    t[propName] = propValue
    return t

  class Klass
    constructor: (@name, @primitive, @constrFn, @defaultValue) ->

    getConstrFn: () ->
      this.__tryResolve() if @primitive == undefined
      return @constrFn

    getDefaultValue: () ->
      this.__tryResolve() if @primitive == undefined
      return @defaultValue

    __tryResolve: () ->
        sig = Sunny.Meta.findSig(@name)
        if sig
          @primitive = false
          @constrFn = sig.__meta__.klass.constrFn
          @defaultValue = sig.__meta__.klass.defaultValue

  class Enum extends Klass
    constructor: (name, valuesArr) ->
      super(name, true, null, valuesArr[0])
      @values = valuesArr
      Sunny.Utils.safeReg(this, val, val) for val in valuesArr

    ord: (e) -> findIndex @values, (ee) -> e == ee
    lte: (e1, e2) -> this.w_ords e1, e2, (i1, i2) -> i1 <= i2
    lt:  (e1, e2) -> this.w_ords e1, e2, (i1, i2) -> i1 < i2
    gte: (e1, e2) -> this.w_ords e1, e2, (i1, i2) -> i1 >= i2
    gt:  (e1, e2) -> this.w_ords e1, e2, (i1, i2) -> i1 > i2

    hasValue: (e) -> this.ord(e) != -1
    valueOf:  (e) -> i = this.ord(e); if i != -1 then @values[i] else undefined

    w_ords: (e1, e2, fn) ->
      i1 = this.ord(e1); return undefined if i1 == -1
      i2 = this.ord(e2); return undefined if i2 == -1
      return fn(i1, i2)

  class Type
    constructor: (@mult, @klasses, @refKind) ->

    isScalar:      ()  -> @mult == "one" || @mult == "lone" || not @mult
    isUnary:       ()  -> @klasses.length == 1
    arity:         ()  -> @klasses.length
    columnKlass:   (i) -> @klasses[i]
    isComposition: ()  -> @refKind == "composition"
    isAggregation: ()  -> @refKind == "aggregation"
    isPrimitive:   ()  -> this.isUnary() && @klasses[0].primitive
    isReference:   ()  -> not this.isPrimitive()

    defaultValue: () ->
      if not this.isScalar()
        return []
      else if @klasses.length > 1
        return []
      else
        return @klasses[0].defaultValue

    domain: () ->
      return this.klasses[0].getConstrFn()

    range: () ->
      return this.klasses[this.klasses.length - 1].getConstrFn()

  __exports__ : ["Int", "Bool", "Real", "DateTime", "Text", "Klass", "Type", "Obj", "Val", "Enum", "enums",
                 "one", "set", "compose", "owns"]

  Klass     : Klass
  Type      : Type
  Enum      : Enum
  Obj       : new Klass "Obj", false, null
  Val       : new Klass "Val", true, null
  Int       : new Klass "Int", true, 0
  Real      : new Klass "Real", true, 0.0
  DateTime  : new Klass "DateTime", true, () -> Date.now()
  Bool      : new Klass "Bool", true, false
  Text      : new Klass "Text", true, null
  isKlass   : (fn) -> typeof(fn) == "function" and fn.__meta__?
  isSubklass: (sub, sup) ->
                return true if sub == sup
                return null unless Sunny.Types.isKlass(sub) and Sunny.Types.isKlass(sup)
                return false unless sub.__super__
                return Sunny.Types.isSubklass(sub.__super__.constructor, sup)
  isSigKls    : (kls) -> Sunny.Types.isSubklass(kls, Sunny.Model.Sig)
  isRecordKls : (kls) -> Sunny.Types.isSubklass(kls, Sunny.Model.Record)
  isMachineKls: (kls) -> Sunny.Types.isSubklass(kls, Sunny.Model.Machine)
  isEventKls  : (kls) -> Sunny.Types.isSubklass(kls, Sunny.Model.Event)

  asType    : (x) -> if x instanceof Type
                       return x
                     else if x instanceof Klass
                       return new Type("lone", [x])
                     else if typeof(x) == "string"
                       return new Type("lone", [new Klass(x)])
                     else if Sunny.Types.isKlass(x)
                       return new Type("lone", [x.__meta__.klass])
                     else if x instanceof Array
                       colKlasses = map x, (e) -> Sunny.Types.asType(e).klasses[0]
                       return new Type("set", colKlasses)
                     else
                       return null
  set       : (t) -> return setTypeProperty(t, "mult", "set")
  one       : (t) -> return setTypeProperty(t, "mult", "one")
  compose   : (t) -> return setTypeProperty(t, "refKind", "composition")
  owns      : (t) -> return Sunny.Types.compose(t)

  # enums     : () -> ans = new Enum(arguments); ans[key] = key for key in arguments; ans

  enums : (hash) ->
    for key, vals of hash
      e = new Enum(key, vals)
      this[key] = e
      registerKW(key, e)

Sunny.simport(this, Sunny.Types)

# -----------------------------------------------

findFieldByName = (fields, name) -> fields.find((f) -> f.name == name)

convertMeteorObj = (sunnyCls, meteorObj) ->
  return meteorObj unless meteorObj
  return (sunnyCls || Sunny.Model.Record).new(meteorObj)

convertObj = (sunnyCls, obj) ->
  return obj unless obj
  return obj if obj instanceof Sunny.Model.Sig
  if sunnyCls or obj?._sunny_type
    obj = convertMeteorObj(sunnyCls, obj)
    obj = null if obj.isGhost()
  return obj

# takes an array of raw (JSON) objects (as stored in Mongo DB)
# and converts them to Sunny records
convertMeteorArray = (sunnyCls, arr, elemMapFn) ->
  mapFn = elemMapFn || convertMeteorObj
  ans = []
  dangling = []
  idx = -1
  for e in arr
    idx = idx + 1
    me = mapFn(sunnyCls, e)
    if me
      ans.push(me)
    else
      dangling.push(elem: e, idx: idx)
  return result: ans, dangling: dangling

wrap = (obj, fld, val) ->
  if not fld.type.isUnary()
    # ------------------------------
    #  higher arity
    # ------------------------------
    val = [] unless val
    ans = []
    for tuple in val
      unless tuple instanceof Array
        msg = "value not array of arrays for field #{fld} of arity #{fld.type.arity}"
        sdebug(msg); throw(msg)
      unless tuple.length == fld.type.arity()
        msg = "arity mismatch on field #{fld}: arity=#{fld.type.arity}, tuple length=#{tuple.length}"
        sdebug msg; throw(msg)
      idx = -1
      convTuple = []
      for e in tuple
        idx = idx + 1
        kls = fld.type.columnKlass(idx)
        sunnyCls = kls.getConstrFn()
        convTuple.push convertObj(sunnyCls, e)
      ans.push createSunnyArray(null, fld, convTuple)
    return createSunnyArray(obj, fld, ans)
  else
    if fld.type.isScalar()
      # ------------------------------
      # unary scalar
      # ------------------------------        
      if fld.type.isPrimitive()
        return val
      else
        return convertObj(fld.type.domain(), val)
    else
      # ------------------------------
      # unary array
      # ------------------------------    
      val = [] unless val
        # obj.writeField(fld.name, val)
      throw("field #{fld.name} in #{obj} has no type") unless fld.type
      throw("field #{fld.name} in #{obj} is not unary") unless fld.type.isUnary()
      ans = convertMeteorArray(fld.type.domain(), val, convertObj)
      sa = createSunnyArray(obj, fld, ans.result)
      # for d in ans.dangling
      #   sa._updateMongo("$pull", d.elem)
      return sa

createSunnyArray = (sunnyOwnerObj, sunnyFld, array) ->
  ans = array || []
  ans.super = {}
  ans.__sunny__ = { owner: sunnyOwnerObj, field: sunnyFld }
  # extra functions defined in SunnyArrayExt
  for pn, pv of Sunny.Model.SunnyArrayExt.prototype
    ans[pn] = pv
  # existing Array functions
  for pn in Object.getOwnPropertyNames(Array.prototype)
    pv = Array.prototype[pn]
    pv = pv.bind(ans) if typeof(pv) == "function"
    ans.super[pn] = pv
  # join functions for all fields defined for the type of this field
  if sunnyFld.type?.isReference()
    allFldNames = {}
    for e in ans
      if e && e.meta?()
        for f in e.meta().allFields()
          allFldNames[f.name] = f.name
    for fname of allFldNames
      do (fname) ->
        if not ans.hasOwnProperty(fname)
          Object.defineProperty(ans, fname, {
            enumerable: true,
            get: () -> mapFilter ans, (e) -> e.readField(fname)
          })
  return ans

Sunny.MetaModel = do ->
  # -----------------------------------------------------------------
  #   class Field
  # -----------------------------------------------------------------
  class Field
    # @param name [String]
    # @param type [Sunny.Types.Type]
    constructor: (@name, @type) ->

    read_policy:   (fn) -> this.policy read: fn
    update_policy: (fn) -> this.policy update: fn
    policy: (hash) ->
      return this.policy.bind(this) if hash == undefined
      pre = hash._precondition
      delete hash._precondition
      for op, fn of hash
        switch op
          when "read", "update", "push", "pull"
            p = new Sunny.Model.FldPolicy(this, op, @name, fn, pre)
            Sunny.Meta.policies.push(p)
          else
            throw("unrecognized operation: #{op}")

  # -----------------------------------------------------------------
  #   class RecordMeta
  # -----------------------------------------------------------------
  class RecordMeta
    constructor: (fn, parentFn) ->
      @__repr__      = null
      @__pubs__      = {} # ConnId -> Meteor Publisher
      @__comps__     = {} # ConnId -> (String -> String -> Sunny.Deps.Comp)
      @__pubObjs__   = {} # ConnId -> (String -> _)  (published objects for clients)
      @__objDeps__   = {} # ObjId -> FldName -> Sunny.Deps.Dep
      @__findDep__   = new Sunny.Deps.Dep("#{fn.name}::find")
      @klass         = new Sunny.Types.Klass(fn.name, false, fn, null)
      @name          = fn.name
      @relative_name = fn.name
      @sigCls        = fn
      @parentSig     = parentFn
      @subsigs       = []
      @fields        = []
      @staticBlock   = null

    repr:        () -> @__repr__ #if Meteor.isServer then @__repr__ else @__repr__._collection

    hasOwnField: (fieldName) -> findFieldByName(this.fields, fieldName)
    hasField:    (fieldName) -> findFieldByName(this.allFields(), fieldName)
    field:       (fieldName) -> this.hasField(fieldName)
    allFields:   () -> this._all("fields", "allFields")
    allParams:   () -> this._all("params", "allParams")
    addField:    (fld) ->
      @fields.push fld
      sig = @sigCls
      while sig
        Sunny.Utils.safeReg sig, fld.name, fld
        sig = sig.__meta__?.parentSig

    _deleteObjDeps:          (objId)  -> delete @__objDeps__[objId]

    _deletePublishers:       (connId) -> delete @__pubs__[connId]
    _deletePublishedObjects: (connId) -> delete @__pubObjs__[connId]
    _deleteComputations:     (connId) ->
      for key1, fcomps of @__comps__[connId]
        for key2, comp of fcomps
          comp.stop()
      delete @__comps__[connId]

    _cleanupConn: (connId) ->
      this._deletePublishedObjects(connId)
      this._deleteComputations(connId)
      this._deletePublishers(connId)

    _getPubObjs: (connId) -> @__pubObjs__[connId] ?= {}

    _getComp: (connId, objKey, fldKey, mkCompFn) ->
      connComps = @__comps__[connId] ?= {}
      objComps = connComps[objKey] ?= {}
      objComps[fldKey] ?= mkCompFn()

    _getObjFldComp: (connId, objId, fldName) ->
      self = this
      this._getComp connId, objId, fldName, () ->
        new Sunny.Deps.FldComp(connId, self.sigCls.new(_id: objId), self.field(fldName))

    _getSigFindComp: (connId) ->
      self = this
      this._getComp connId, ":find:", "set", () ->
        new Sunny.Deps.FindComp(connId, self.sigCls)

    _getObjFldDeps: (objId, fldName) ->
      depName = "#{@name}(#{objId}).#{fldName}::change"
      objFldDeps = @__objDeps__[objId] ?= {}
      objFldDeps[fldName] ?= new Sunny.Deps.Dep(depName)

    _all: (fName, mName) ->
      mine = this[fName] || []
      if this.parentSig
        inherited = this.parentSig.__meta__[mName]()
        return inherited.concat(mine)
      else
        return mine

  # -----------------------------------------------------------------
  #   class EventMeta
  # -----------------------------------------------------------------
  class EventMeta extends RecordMeta
    constructor: () ->
      super
      @params = []

    fromField: () -> this._toFromField("from")
    toField:   () -> this._toFromField("to")

    _toFromField: (toFrom) ->
      fname = "_#{toFrom}Field"
      if this.hasOwnProperty(fname)
        return this[fname]
      else if typeof(this.parentSig?.__meta__._toFromField) == "function"
        return this.parentSig.__meta__._toFromField(toFrom)
      else
        return null

  __exports__ : ["RecordMeta", "EventMeta", "Field"]
  RecordMeta  : RecordMeta
  EventMeta   : EventMeta
  Field       : Field

Sunny.simport(this, Sunny.MetaModel)

Sunny.Model = do ->
  rc = (r, isEvent) ->
    metaConstrFn = RecordMeta
    metaConstrFn = EventMeta if isEvent
    r.__meta__ = new metaConstrFn(r, r.__super__?.constructor)
    addStaticMethods(r)
    register(r)
    return r

  ec = (e) -> rc(e, true)

  # -----------------------------------------------------------------
  #   class Sig
  # -----------------------------------------------------------------
  rc class Sig
    init: (props) ->
      this._defProps()
      this._setProp(f.name, undefined) for f in this.meta().allFields()
      this._setProps(props)
      return this

    meta: -> this.constructor.__meta__

    readField:  (fldName, opts) ->
      this._defProps()
      this.__props__[fldName]

    writeField: (fldName, fldValue, opts) ->
      return this if @trans
      this._setProp fldName, fldValue

    _setProp: (propName, propValue) ->
      this._defProps()
      this.__props__[propName] = propValue
      # @trans = true
      # this[propName] = propValue
      # @trans = false
      return this

    _defProps: () ->
      if not this.__props__
        Object.defineProperty(this, '__props__', {enumerable:false , value:{}})

    _setProps: (props) ->
      this._setProp pn, pv for pn, pv of props
      return this

    __static__: {
      new:        (props)   ->
        sig = this._findAltSig(props?._sunny_type)
        new sig().init(props)
      readField:  (args...) -> null
      writeField: (args...) -> null
      _findAltSig: (sigName) -> Sunny.Meta.findSig(sigName) || this

    }

  # -----------------------------------------------------------------
  #   class Record
  # -----------------------------------------------------------------
  rc class Record extends Sig
    # ------------------------------------------------------------------------
    init: (props) ->
      this._defProps()
      sigName = this.meta().name
      for fld in this.meta().allFields()
        this._setProp fld.name, fld.type?.defaultValue()
      this._setProp "_sunny_type", sigName
      this._setProps(props)
      return this

    # ------------------------------------------------------------------------
    # @return string
    id:   () -> this.__props__._id

    # ------------------------------------------------------------------------
    # @return string
    type: () -> this.__props__?._sunny_type

    # ------------------------------------------------------------------------
    # Check if the object still exists in the DB.
    #
    # @return boolean
    #   - true if the object is missing in the DB, false otherwise
    isGhost: () -> this.meta().repr().findOne({_id: this.id()}, {_id: 1}) == undefined

    # ---------------- EJSON methods ---------------
    typeName:    () -> this.type()
    toJSONValue: () -> this._toMeteorRef()
    clone:       () -> this.meta().sigCls.new(this.toJSONValue())
    equals: (other) ->
      return false unless other
      return false unless this.constructor == other.constructor
      return this.id() == other.id()

    # ------------------------------------------------------------------------
    readField: (fldName) ->
      # handles the case when properties of the prototype are being enumerated
      return this.meta().field(fldName)?.type unless this.__props__
      Sunny.CRUD.readField(this, fldName)

    # ------------------------------------------------------------------------
    writeField: (fldName, fldValue) ->
      hash = {}; hash[fldName] = fldValue
      Sunny.CRUD.writeField(this, hash)

    # ------------------------------------------------------------------------
    destroy:  () -> Sunny.CRUD.delete(this)
    _destroy: () -> Sunny._CRUD.delete(this)

    # ------------------------------------------------------------------------
    toString: () -> "#{this.meta().name}(#{this.id()})"
    inspect:  () -> "#{this.meta().name}.new({_id: '#{this.id()}'})"

    _raw: (projection) ->
      projection = {} if projection == undefined
      this.meta().repr().findOne({_id: this.id()}, projection)

    _serFieldsForClient: (connId, flds) ->
      flds = this._raw() if flds == undefined
      okFlds = {}
      for fldName, fldVal of flds
        if fldName == "_sunny_type" or fldName == "_id"
          okFlds[fldName] = fldVal
        else
          fld = this.meta().field(fldName)
          continue if not fld # should not happen
          ans = this._serFieldForClient(connId, fld, fldVal)
          okFlds[fldName] = ans if ans != undefined
      return okFlds

    _serFieldForClient: (connId, fld, fldVal) ->
      fldComp = this.meta()._getObjFldComp(connId, this.id(), fld.name)
      fldComp.exe(fldVal)

    _toMeteorRef: () -> _id: this.id(), _sunny_type: this.type()
    _inspect:     () -> "Sunny.Meta.records['#{this.meta().name}'].new({_id: '#{this.id()}'})"

    __static__: {
        create:     (objProps)  -> Sunny.CRUD.create(this, objProps)
        destroyAll: ()          -> r.destroy() for r in this.all()

        # only locally
        _create:     (objProps) -> Sunny._CRUD.create(this, objProps)
        _destroyAll: ()         -> r._destroy() for r in this.all()

        all: (opts) ->
          ans = this.find({}, opts)
          ans

        find: (selector, opts) ->
          if meta = this.__meta__
            meta.__findDep__.depend()
            mList = meta.repr().find(selector, opts).fetch();
            convertMeteorArray(this, mList).result;
          else
            return []

        findOne: (selector, opts) ->
          if meta = this.__meta__
            meta.__findDep__.depend()
            ans = meta.repr().findOne(selector, opts)
            return convertMeteorObj(this, ans);
          else
            return undefined

        findById: (id) ->
          return this.findOne(_id: id)

        create_policy: (hash) -> this.policy create: hash
        read_policy:   (hash) -> this.policy read: hash
        update_policy: (hash) -> this.policy update: hash
        delete_policy: (hash) -> this.policy delete: hash
        policy: (hash) ->
          pre = hash._precondition
          delete hash._precondition
          for op, pol of hash
            ps = switch op
              when "create", "find"
                [new Sunny.Model.SigPolicy(this,op,pol,pre)]
              when "delete"
                [new Sunny.Model.ObjPolicy(this,op,pol,pre)]
              when "read", "update", "push", "pull"
                new Sunny.Model.FldPolicy(this,op,f,fn,pre) for f,fn of pol
              else
                throw("unrecognized operation: #{op}")
                []
            for p in ps
              Sunny.Meta.policies.push(p)
    }

  # -----------------------------------------------------------------
  #   class Machine
  # -----------------------------------------------------------------
  rc(class Machine extends Record)

  # -----------------------------------------------------------------
  #   class Event
  # -----------------------------------------------------------------
  ec class Event extends Sig
    init: (props) ->
      # TODO: don't hardcode
      # this.setFrom(Sunny.myClient())
      # this.setTo(Sunny.myServer())
      super
      return this

    setFrom: (from) -> this[this.meta().fromField()] = from
    setTo:   (to)   -> this[this.meta().toField()] = to

    paramValues: () ->
      ans = {}
      ans[pname] = this[pname] for pname in this.meta().allParams()
      return ans

    paramValuesJSON: () ->
      ans = {}
      ans[pname] = EJSON.toJSONValue(this[pname]) for pname in this.meta().allParams()
      ans

    # ---------------- EJSON methods ---------------
    typeName:    () -> this.meta().name
    toJSONValue: () -> event: this.typeName() , params: this.paramValuesJSON()
    clone:       () -> this.meta().sigCls.new(this.paramValues())
    equals: (other) ->
      return false unless other
      return false unless this.constructor == other.constructor
      return EJSON.equals(this.paramValues(), other.paramValues())

    # -----------------------------------------------

    _checkRequires: (cstr) ->
      if cstr != Event
        err = this._checkRequires(cstr.__super__.constructor)
        return err if err
      return null unless cstr.prototype.requires
      cstr.prototype.requires.call(this)

    _trigger: (props) ->
      this._setProps(props) if props
      this.setFrom(Sunny.myClient())
      this.setTo(Sunny.myServer())
      err = this._checkRequires(this.constructor)
      if (err)
        sdebug("precondition to event #{this} failed: '#{err}'")
        Sunny.ACL.signalAccessDenied
          type: "precondition"
          event: this
          msg:   err
        return false
      return this.ensures()

    trigger: (props) ->
      # this._setProps(props)
      # this._trigger()
      # TODO: FIXME
      if Meteor.isServer
        self = this
        Sunny.Queue.runAsInvocation "event", () -> self._trigger(props)
      else
        this._setProps(props)
        Meteor.apply("event", [this], Sunny.Queue._rpcOpts)

  # -----------------------------------------------------------------
  #   class PolicyOutcome
  # -----------------------------------------------------------------
  class PolicyOutcome
    constructor:  (@allowed, @value, @denyReason) ->
    isAllowed:    () -> @allowed == true
    isDenied:     () -> not this.isAllowed()
    isNA:         () -> false
    hasValue:     () -> @value != undefined
    toString:     () ->
      if this.isDenied() then "Denied"
      else if this.hasValue() then "Restricted"
      else "Allowed"
    returnResult: (allowedVal, deniedVal) ->
      if @allowed != true
        deniedVal
      else if @value == undefined
        allowedVal
      else
        @value
  # -----------------------------------------------------------------
  #   class Op
  # -----------------------------------------------------------------
  class Op
    constructor: (name, params) ->
      @name = name
      @argNames = []
      for pn, pv of params
        @argNames.push(pn)
        this[pn] = pv

    args: ()              -> this[argName] for argName in @argNames
    argsHashOp: ()        -> this.argsHash("op")
    argsHash: (opNameKey) ->
      ans = {}
      ans[opNameKey] = @name if opNameKey
      ans[pn] = this[pn] for pn in @argNames
      ans
    toString: () ->
      ans = "#{@name}"
      ans += " #{@sig.name}" if @sig
      ans += " #{@obj}"      if @obj
      ans += ".#{@fldName}"  if @fldName
      ans
    equals: (other) ->
      return false unless other
      return false unless this.constructor == other.constructor
      return false unless this.name == other.name
      return false unless this.sig == other.sig
      return false unless _equalsFn(this.obj)(other.obj)
      return false unless this.fldName == other.fldName
      return true

  class OpCreate extends Op
    constructor: (sig) -> super("create", sig: sig)

  class OpFind extends Op
    constructor: (sig, val) -> super("find", val: val, sig: sig)

  class OpRead extends Op
    constructor: (obj, fldName, val) -> super("read", {obj: obj, val: val, fldName: fldName})

  class OpUpdate extends Op
    constructor: (obj, fldName, val) -> super("update", {obj: obj, val: val, fldName: fldName})

  class OpDelete extends Op
    constructor: (obj) -> super("delete", {obj: obj})

  class OpArrPush extends Op
    constructor: (obj, fldName, val) -> super("push", {obj: obj, val: val, fldName: fldName})

  class OpArrPull extends Op
    constructor: (obj, fldName, val) -> super("pull", {obj: obj, val: val, fldName: fldName})

  # -----------------------------------------------------------------
  #   class Policy
  # -----------------------------------------------------------------
  class Policy
    checkOpName: (op) -> op.name == @op
    checkSig:    (op) -> this._isSubSig(op.sig)
    checkObj:    (op) -> this._isSubSig(op.obj?.meta?().sigCls)
    checkPre:    (op) -> not @precondition or @precondition.apply(this._mkContext(), op.args())

    applies: (op) ->
      this.checkOpName(op) and
      this.checkSig(op) and
      this.checkObj(op) and
      this.checkPre(op)

    check: (op) ->
      ctx = this._mkContext(op.argsHashOp())
      ans = @checkerFn.apply(ctx, op.args())
      return this._toPolicyOutcome(ans)

    _isSubSig: (sig) -> Sunny.Types.isSubklass(sig, @sig)

    _mkContext:   (extraHash) ->
      ans =
        allow:  (newVal) -> new PolicyOutcome(true, newVal)
        deny:   (reason) -> new PolicyOutcome(false, undefined, reason)
        client: Sunny.myClient()
        server: Sunny.myServer()
      ans[p] = pv for p, pv of extraHash
      ans

    _toPolicyOutcome: (x) ->
      if x instanceof PolicyOutcome
        x
      else if typeof(x) == "string"
        new PolicyOutcome(false, undefined, x)
      else if typeof(x) == "boolean"
        new PolicyOutcome(false)
      else
        throw("invalid result from a policy checker: #{x} (#{typeof(x)})")

  # -----------------------------------------------------------------
  #   class SigPolicy
  # -----------------------------------------------------------------
  class SigPolicy extends Policy
    constructor: (@sig, @op, @checkerFn, @precondition) ->
    checkObj:    (op) -> true # op.obj need not be set for sig policy

  # -----------------------------------------------------------------
  #   class ObjPolicy
  # -----------------------------------------------------------------
  class ObjPolicy extends Policy
    constructor: (@sig, @op, @checkerFn, @precondition) ->
    checkSig: (op) -> true # op.sig need not be set for sig policy

  # -----------------------------------------------------------------
  #   class FldPolicy
  # -----------------------------------------------------------------
  class FldPolicy extends ObjPolicy
    constructor: (sig, op, fldSelector, checkerFn, precondition) ->
      super sig, op, checkerFn, precondition
      @fld = fldSelector
      toChecker = (sel) ->
        sel = sel.trim()
        switch
          when typeof(sel) == "function" then return sel
          when typeof(sel) == "string"
            # matches any field
            if sel == "*"
              (fname) -> true
            # single regular expression as string
            else if sel[0] == "/" and sel[sel.length-1] == "/"
              toChecker(new RegExp(sel.substring(1, sel.length-1)))
            else if sel[0] == "!"
              c1 = toChecker(sel.substring(1))
              (fname) -> not c1(fname)
            else
              conds = sel.split /[,\s]+/
              # exact string
              if conds.length == 1
                exactName = conds[0]
                (fname) -> exactName == fname
              # either one of the comma-separated choices
              else
                checkers = map conds, (cond) -> toChecker(cond)
                (fname) -> (findFirst checkers, (ch) -> ch(fname))?
          # regular expression
          when sel instanceof RegExp
            re = new RegExp("^" + sel.source + "$")
            (fname) -> re.test(fname)
          else
            throw("illegal field selector: #{sel} (#{typeof(sel)})")
      @fldChecker = toChecker(fldSelector)

    checkOpName: (op) ->
      op.name == @op and @fldChecker(op.fldName)

  # -----------------------------------------------------------------
  #   class SunnyArrayExt
  # -----------------------------------------------------------------
  class SunnyArrayExt
    _myOwner:   () -> this.__sunny__.owner
    _myFld:     () -> this.__sunny__.field
    _myFldName: () -> this.__sunny__.field.name

    _updateMongo: (op, query) ->
      fld = this.__sunny__.field
      obj = this.__sunny__.owner
      # check = Sunny.ACL.check_update(obj, fld.name, this)
      mod = {}
      mod[op] = {}
      mod[op][fld.name] = query
      applyDbOp "update", obj.meta().repr(), { _id: obj.id() }, mod
      return this

    push: (e) ->
      obj = this._myOwner()
      fname = this._myFldName()
      if Sunny.CRUD.arrayFieldPush(obj, fname, e)
        this.super.push(e)
        obj._setProp fname, this
      return this

    # splice: (pos, len) ->
    #   obj = this._myOwner()
    #   fname = this._myFldName()
    #   if Sunny.CRUD.arrayFieldSplice(obj, fname, pos, len)
    #     this.super.splice(pos, len)
    #     obj._setProp fname, this

    remove: (elem) ->
      idx = findIndex this, _equalsFn(elem)
      if idx != -1
        obj = this._myOwner()
        fname = this._myFldName()
        if Sunny.CRUD.arrayFieldPull(obj, fname, elem)
          this.splice(idx, 1)
          obj._setProp fname, this
        else
          idx = -2
      return idx

    contains: (obj) ->
      return this.findIndex(_equalsFn(obj)) != -1

    containsAll: (arr) ->
      for obj in arr
        return false if not this.contains(obj)
      return true

    all: (fn) ->
      for elem in this
        return false if not fn(elem)
      return true

    some: (fn) ->
      for elem in this
        return true if fn(elem)
      return false

    first: () -> this[0]
    last:  () -> this[this.length-1]

    groupByDomain: () -> groupByKey(this, 0)
    groupByRange: () -> groupByKey(this, 1)

  Sig           : Sig
  Record        : Record
  Machine       : Machine
  Event         : Event
  PolicyOutcome : PolicyOutcome
  Policy        : Policy
  SigPolicy     : SigPolicy
  ObjPolicy     : ObjPolicy
  FldPolicy     : FldPolicy
  Op            : Op
  OpCreate      : OpCreate
  OpFind        : OpFind
  OpRead        : OpRead
  OpUpdate      : OpUpdate
  OpDelete      : OpDelete
  OpArrPush     : OpArrPush
  OpArrPull     : OpArrPull
  SunnyArrayExt : SunnyArrayExt

Sunny.simportAll(this, Sunny.Model)

# ====================================================================================
#   Sunny.Meta
# ====================================================================================
Sunny.Meta = do ->
  records:  {}
  machines: {}
  events:   {}
  policies: []
  _userKls:   null
  _clientKls: null
  _serverKls: null
  userKls:   () -> Sunny.Meta._userKls || Sunny.Dsl.SunnyUser
  clientKls: () -> Sunny.Meta._clientKls || Sunny.Dsl.SunnyClient
  serverKls: () -> Sunny.Meta._serverKls || Sunny.Dsl.SunnyServer

  recordsAndMachines: () ->
    ans = {}
    ans[name] = kls for name, kls of Sunny.Meta.records
    ans[name] = kls for name, kls of Sunny.Meta.machines
    return ans

  recordsAndMachinesAndBuiltin: () ->
    ans = Sunny.Meta.recordsAndMachines()
    builtin = [Sunny.Dsl.SunnyUser, Sunny.Dsl.SunnyClient, Sunny.Dsl.SunnyServer]
    ans[kls.name] = kls for kls in builtin
    return ans

  findSig: (name) ->
    return null unless name
    return this.records[name] || this.machines[name] || this.events[name]

# ====================================================================================
#   Sunny.Dsl
# ====================================================================================
Sunny.Dsl = do ->
  createRecordKls = (kls, parent=Record) ->
    [sig, parentSig] = fixKlsParent(kls, parent)

    # create meta
    sig.__meta__ = new RecordMeta(sig, parentSig)
    sig.__meta__.__repr__ = new Meteor.Collection("#{sig.name}")

    updateParentsSubsigs(sig, parentSig)
    addStaticMethods(sig)
    addFieldsAndMethods(sig, parentSig)
    register(sig)

    # add EJSON type
    EJSON.addType sig.__meta__.name, (json) ->
      deserializedParams = {}
      deserializedParams[pn] = EJSON.fromJSONValue(pv) for pn, pv of json
      sig.new(deserializedParams)

    return sig

  createMachineKls = (kls) ->
    createRecordKls(kls, Machine)

  createEventKls = (kls, parent) ->
    [sig, parentSig] = fixKlsParent(kls, parent)
    sig.__meta__ = new EventMeta(sig, parentSig)

    updateParentsSubsigs(sig, parentSig)
    addStaticMethods(sig)

    for toFrom in ["from", "to"]
      if sig.prototype.hasOwnProperty(toFrom)
        flds = extractFieldEntries(sig.prototype[toFrom])
        sfatal("must specify exactly one '#{toFrom}' field") unless flds.length == 1
        sig.__meta__.addField(flds[0])
        sig.__meta__["_#{toFrom}Field"] = flds[0].name
        defineFldProperty(sig, flds[0].name)
        defineFldProperty(sig, flds[0].name, toFrom)
        delete sig.prototype[toFrom]

    paramNames = []
    paramFlds = extractFieldEntries(sig.prototype.params)
    delete sig.prototype["params"]
    paramFlds = paramFlds.concat(extractFieldEntries(sig.prototype))
    for paramFld in paramFlds
      sig.__meta__.fields.push paramFld
      defineFldProperty(sig, paramFld.name)
      paramNames.push paramFld.name
    sig.__meta__.params = paramNames

    register(sig)

    # add EJSON type
    EJSON.addType sig.__meta__.name, (json) ->
      deserializedParams = {}
      deserializedParams[pn] = EJSON.fromJSONValue(pv) for pn, pv of json.params
      sig._findAltSig(json.event).new(deserializedParams)

    return sig

  createKls = (body, createFn, defaultSuper, registry) ->
    kls = createFn(body, defaultSuper)
    registry[kls.name] = kls if registry
    return kls

  registerKlsAllHelper = (kls) ->
    UI.registerHelper kls.name, () -> kls.all()

  _record = (body, defaultSuper) ->
    kls = createKls(body, createRecordKls, defaultSuper || Record, Sunny.Meta.records)
    registerKlsAllHelper(kls)
    return kls

  _machine = (body, defaultSuper) ->
    createKls(body, createRecordKls, defaultSuper || Machine, Sunny.Meta.machines)

  _event = (body, defaultSuper) ->
    evKls = createKls(body, createEventKls, defaultSuper || Event, Sunny.Meta.events)

    # Register Meteor template helpers
    if Meteor.isClient
      UI.registerHelper evKls.name, (kw) ->
        params = kw?.hash
        ev = evKls.new(params)
        UI._globalHelpers["sunny_eventMeta"](hash: {event: ev})

      # helpers for each param
      for pName in evKls.__meta__.allParams()
        do(pName) ->
          UI.registerHelper "#{evKls.name}_#{pName}", (ctx) ->
            if not ctx
              return "sunny-event-param": "#{evKls.name}.#{pName}"
            else
              return {}

    return evKls

  record:  (x) -> _record(x)
  machine: (x) -> _machine(x)
  event:   (x) -> _event(x)

  user:    (x) -> x = _record(x,  Sunny.Dsl.SunnyUser);   Sunny.Meta._userKls = x;   x
  client:  (x) -> x = _machine(x, Sunny.Dsl.SunnyClient); Sunny.Meta._clientKls = x; x
  server:  (x) -> x = _machine(x, Sunny.Dsl.SunnyServer); Sunny.Meta._serverKls = x; x

  create_policy: (target, body) -> target.create_policy(body)
  read_policy:   (target, body) -> target.read_policy(body)
  update_policy: (target, body) -> target.update_policy(body)
  delete_policy: (target, body) -> target.delete_policy(body)

  policy:  (target, body) ->
    switch
      when target instanceof Field      then target.policy(body)
      when Sunny.Types.isSigKls(target) then target.policy(body)
      else throw("Unknown policy target: #{target}")

  SunnyUser: createRecordKls class SunnyUser extends Record
    _mUser: Obj
    email: Text
    name: Text
    avatar: Text
    
    __static__: {
      findOrCreate: (mUser) ->
        usr = this.findOne("_mUser._id": mUser._id)
        if not usr
          usr = this.create(_mUser: mUser, email: mUser.emails[0].address)
        return usr
    }

  SunnyClient: createMachineKls class SunnyClient extends Machine
    _mConn: Obj
    connId: () -> this._mConn?.id

  SunnyServer: createMachineKls class SunnyServer extends Machine
    onlineClients: set SunnyClient

  SunnyClientEvent: createEventKls class SunnyClientEvent extends Event
    from:
      client: SunnyClient
    to:
      server: SunnyServer


# ====================================================================================
#   Access Control Stuff
# ====================================================================================
Sunny.ACL = do ->
  _checkHistory = new Sunny.Utils.FiberLocalVar("Sunny.ACL.checkHistory")
  _inACLcheck = new Sunny.Utils.FiberLocalVar("Sunny.ACL._inACLcheck")
  _aclCheckStack = new Sunny.Utils.FiberLocalVar("Sunny.ACL._aclCheckStack", {})
  _aclCheckCache = new Sunny.Utils.FiberLocalVar("Sunny.ACL._aclCheckCache", {})

  _accessDeniedListeners = []
  _allowByDefault = true
  _allowOutcome = new Sunny.Model.PolicyOutcome(true)
  _denyOutcome  = new Sunny.Model.PolicyOutcome(false, undefined, "denied by default")

  _allowByDefaultOutcome = new Sunny.Model.PolicyOutcome(true)
  _allowByDefaultOutcome._byDefault = true
  _denyByDefaultOutcome = new Sunny.Model.PolicyOutcome(false, undefined, "denied by default")
  _denyByDefaultOutcome._byDefault = true
    
  _addListener = (fn) ->
    throw("not a function: #{fn}") unless typeof(fn) == "function"
    _accessDeniedListeners.push(fn)

  _defaultOutcome = () ->
    if Sunny.ACL.isAllowByDefault() then _allowByDefaultOutcome else _denyByDefaultOutcome

  # _printStack: (stack) ->
  #   pfix = "        "
  #   indt = ""
  #   poly_sdebug "#{pfix} stack size = #{stack.length}"
  #   for op in stack
  #     poly_sdebug "#{pfix}#{indt} #{op.toString()}"
  #     indt = indt + " "

  _printStack = (hash) ->
    pfix = "        "
    for op, v of hash
      poly_sdebug "#{pfix} #{op}: #{hash[op]}"
        
  _findAndCheckPolicies = (op) ->
    poli = Sunny.ACL.applicablePolicies(op)
    if poli.length == 0
      return _defaultOutcome()
    else
      poly_sdebug("policies for #{op}: #{poli.length}")
      currVal = op.val
      currOutcome = null
      for p in poli
        poly_sdebug "  checking policy on behalf of #{Sunny.currClient()}"
        op.val = currVal
        outcome = p.check(op)
        if outcome.isDenied()
          poly_sdebug "  -> denied"
          return outcome # denied; return
        else if outcome.isAllowed()
          msg = "  -> allowed";
          if outcome.hasValue()
            msg = msg + " (restricted)"
            msg += ": #{outcome.value.length}" if outcome.value instanceof Array
          poly_sdebug msg
          currOutcome = outcome if not currOutcome
          if outcome.hasValue()
            currVal = if op.obj
                        wrap(op.obj, op.obj.meta().field(op.fldName), outcome.value)
                      else
                        outcome.value
            currOutcome = outcome
            currOutcome.value = currVal
       if currOutcome # allowed
        return currOutcome
      else
        return _defaultOutcome()

  lastCheck: () ->
    arr = _checkHistory.get([])
    if arr.length == 0
      return null
    else
      return arr[arr.length - 1]

  lastOutcome:      () -> Sunny.ACL.lastCheck()?.outcome
  lastReadOutcome:  () -> findLast(_checkHistory.get([]), (e) -> e.op.name == "read")?.outcome
  lastWriteOutcome: () -> findLast(_checkHistory.get([]), (e) -> e.op.name == "update")?.outcome

  signalAccessDenied:    (params) -> fn(params) for fn in _accessDeniedListeners
  setAccessDeniedCb:     (cb)     -> _accessDeniedListeners = []; _addListener(cb) if cb
  onAccessDenied:        (cb)     -> _addListener(cb)
  accessDeniedListeners: ()       -> _accessDeniedListeners

  isAllowByDefault:   () -> _allowByDefault
  isDenyByDefault:    () -> not Sunny.ACL.isAllowByDefault()

  applicablePolicies: (op) -> filter Sunny.Meta.policies, (p) -> p.applies(op)

  invalidateCache:    () -> _aclCheckCache.set({}); 

  check_create: (sig)               -> Sunny.ACL.check(new OpCreate(sig))
  check_find:   (sig, records)      -> Sunny.ACL.check(new OpFind(sig, records))
  check_read:   (obj, fldName, val) -> Sunny.ACL.check(new OpRead(obj, fldName, val))
  check_update: (obj, fldName, val) -> Sunny.ACL.check(new OpUpdate(obj, fldName, val))
  check_delete: (obj)               -> Sunny.ACL.check(new OpDelete(obj))
  check_push:   (obj, fldName, val) -> Sunny.ACL.check(new OpArrPush(obj, fldName, val))
  check_pull:   (obj, fldName, val) -> Sunny.ACL.check(new OpArrPull(obj, fldName, val))
  check:        (op) ->
    outcome = do ->
      return _allowOutcome unless Sunny.myClient() # executing on behalf of Server -> ok
      return _allowOutcome if _inACLcheck.get(false)
      _inACLcheck.set(true)
      # opStr = op.toString();
      # stack = _aclCheckStack.get()
      # cache = _aclCheckCache.get()
      # cached = cache[opStr]
      # if cached
      #   poly_sdebug "-------------- returning from cache for op #{op}: #{cached}"
      #   return cached 
      # if stack[op.toString()]
      #   poly_sdebug "********** ACL stack contains op #{op} ---> allowing"
      #   return _allowOutcome 
      # stack[op.toString()] = true
      # poly_sdebug "@@@@@@@@ pushing #{op} to ACL stack"
      # _printStack(stack)
      try
        ans = _findAndCheckPolicies(op)
        # cache[opStr] = ans
        ans
      finally
        _inACLcheck.set(false)
        # delete stack[op.toString()]
        # poly_sdebug "@@@@@@@@ popped #{op} from the ACL stack"
        # Sunny.ACL.invalidateCache() if Object.keys(stack).length == 0

    _checkHistory.push op: op, outcome: outcome
    return outcome

# ====================================================================================
#   _CRUD
# ====================================================================================
Sunny._CRUD = do ->

  create: (sig, props) ->
    sig = Sunny.Utils.toSig(sig)
    check = Sunny.ACL.check_create(sig)
    if check.isAllowed()
      pps = {}
      pps._id = props._id if props?._id
      obj = sig.new(pps)
      objid = applyDbOp "insert", obj.meta().repr(), obj.__props__
      obj._setProp "_id", objid
      onServerBehalf () ->
        obj[pn] = pv for pn, pv of props
      return obj
    else
      Sunny.ACL.signalAccessDenied
        type:    "create"
        sigName: sig.__meta__.name
        msg:     check.denyReason
      return null
  
  delete: (obj) ->
    check = Sunny.ACL.check_delete(obj)
    if check.isAllowed()
      for fld in obj.meta().allFields()
        if fld.type?.isComposition() && not fld.type.isPrimitive()
          refs = obj.readField(fld.name)
          refs = [refs] if fld.type.isScalar()
          for ref in refs
            if ref instanceof Sunny.Model.Record
              ref.destroy()
      applyDbOp "remove", obj.meta().repr(), {_id: obj.id()}
    else
      Sunny.ACL.signalAccessDenied
        type:    "delete"
        sigName: obj.meta().name
        msg:     check.denyReason
      return null
    
  readField: (obj, fldName) ->
    fld = Sunny.Utils.ensureFld(obj, fldName)
    meta = obj.meta()
    dbObj = meta.repr().findOne(obj.id())
    defVal = fld.type?.defaultValue()
    if not dbObj # check if still exists in db; if obj deleted -> just ignore
      sdebug "get #{meta.name}(#{obj.id()}).#{fldName} failed"
      ans = wrap obj, fld, defVal
    else
      ans = wrap obj, fld, dbObj[fldName]
      meta._getObjFldDeps(obj.id(), fldName).depend()
      check = Sunny.ACL.check_read obj, fldName, ans
      if check.isAllowed()
        ans = check.value if check.hasValue()
      else
        Sunny.ACL.signalAccessDenied
          type: "read"
          sigName: meta.name
          fldName: fldName
          msg:  check.denyReason
        ans = defVal
    obj._setProp fldName, ans
    return ans

  writeField: (obj, fldNameValueHash) ->
    mod = {}
    okFldCnt = 0
    for fname, fvalue of fldNameValueHash
      fld = Sunny.Utils.ensureFld(obj, fname)
      check = Sunny.ACL.check_update obj, fname, fvalue
      if check.isAllowed()
        okFldCnt++
        obj._setProp fname, fvalue
        mod[fname] = toMeteorRef(fvalue)        
      else
        Sunny.ACL.signalAccessDenied
          type: "write"
          sigName: obj.meta().name
          fldName: fname
          msg:  check.denyReason
    if okFldCnt > 0
      applyDbOp "update", obj.meta().repr(), { _id: obj.id() }, { $set: mod }
      return true
    else
      return false

  arrayFieldPush: (obj, fname, val) ->
    fld = Sunny.Utils.ensureFld(obj, fname)

    checkPush = Sunny.ACL.check_push obj, fname, val
    checkUpdate = Sunny.ACL.check_update obj, fname 
    check = if checkPush._byDefault then checkUpdate else checkPush
    if check.isAllowed()
      # obj._setProp fname, fvalue
      mod = {}; mod[fname] = toMeteorRef(val)
      applyDbOp "update", obj.meta().repr(), { _id: obj.id() }, { $push: mod }
      return true
    else
      Sunny.ACL.signalAccessDenied
        type: "write"
        sigName: obj.meta().name
        fldName: fname
        msg:  check.denyReason
      return false

  arrayFieldPull: (obj, fname, val) ->
    fld = Sunny.Utils.ensureFld(obj, fname)

    checkPull = Sunny.ACL.check_pull obj, fname, val
    checkUpdate = Sunny.ACL.check_update obj, fname
    check = if checkPull._byDefault then checkUpdate else checkPull
    if check.isAllowed()
      # obj._setProp fname, fvalue
      mod = {}; mod[fname] = toMeteorRef(val)
      applyDbOp "update", obj.meta().repr(), { _id: obj.id() }, { $pull: mod }
      return true
    else
      Sunny.ACL.signalAccessDenied
        type: "write"
        sigName: obj.meta().name
        fldName: fname
        msg:  check.denyReason
      return false

  # arrayFieldSplice: (obj, fname, pos, len) ->
  #   check = Sunny.ACL.check_update obj, fname # Sunny.ACL.check_splice obj, fname, val
  #   if check.isAllowed()
  #     repr = obj.meta().repr()
  #     sel = { _id: obj.id() }
  #     mod1 = {}
  #     for idx in [pos .. pos+len-1]
  #       mod1["#{fname}.#{idx}"] = 1;
  #     repr.update(sel, { $unset: mod1 })
  #     mod2 = {}; mod2["#{fname}"] = null;
  #     repr.update(sel, { $pull: mod2 })
  #     return true
  #   else
  #     Sunny.ACL.signalAccessDenied
  #       type: "write"
  #       sigName: obj.meta().name
  #       fldName: fname
  #       msg:  check.denyReason
  #     return false

  hashFieldSet:     (obj, fldName, propName, propVal) ->
  hashFieldDelete:  (obj, fldName, propName) ->

# ====================================================================================
#   (server only) Sunny.Queue
# ====================================================================================
Sunny.Queue = do ->
  _queue = new Sunny.Utils.FiberLocalVar("Sunny.Queue.queue", [])
  _invIdCnt = 0

  _currInvocation = () -> _queue.peek()
  _rootInvocation = () -> _queue.getAt(0)

  class Invocation
    # @op     :   String
    # @opFn   : Function
    # @args   : Array
    constructor: (op, opFn, args) ->
      @id     = _invIdCnt++
      @op     = op
      @opFn   = opFn
      @args   = args
      @comps  = {}

    addComp: (comp) -> @comps[comp._id] = comp

  currInvocation: _currInvocation
  rootInvocation: _rootInvocation

  enqueueComp: (comp) ->
    inv = _rootInvocation()
    assert inv, "Cannot reschedule computation outside of queued invocations"
    inv.addComp(comp)

  wrapAsInvocation: (op, opFn) ->
    () ->
      self = this
      args = arguments
      connId = this.connection?.id
      Sunny._currConnId.set(connId) if connId
      inv = new Invocation(op, opFn, args)
      _queue.push(inv)
      try
        # tx.start()
        onClientBehalf connId, () ->
          Sunny.ACL.invalidateCache()
          opFn.apply(self, args)
        # tx.commit()
      catch err
        _rootInvocation().error = err
      finally
        assert _queue.pop() == inv, "invocation stack corrupted??!!"
        # top invocation handles errors and reruns invalidated computations
        if _queue.length == 0
          if inv.error
            serror(inv.error)
          else
            Sunny.Deps.rerun(comp) for cId, comp of inv.comps

  runAsInvocation: (op, opFn) ->
    Sunny.Queue.wrapAsInvocation(op, opFn).call(this)

  _rpcOpts: returnStubValue: true, wait: true

# ====================================================================================
#   Sunny.CRUD  -> TODO: rename to Sunny.Ops or something better
#
# Add CRUD methods to Sunny.CRUD so that:
#   (1) on
Sunny.CRUD = {}
# the server delegates the calls to the corresponding Sunny._CRUD methods
if Meteor.isServer
  for op, opFn of Sunny._CRUD
    Sunny.CRUD[op] = Sunny.Queue.wrapAsInvocation(op, opFn)

# the client calls corresponding RPC methods
if Meteor.isClient
  opts = Sunny.Queue._rpcOpts
  for op, opFn of Sunny._CRUD
    do(op, opFn) ->
      if op == "create"
        # special for "create":
        #   (1) serialize the sig argument before invoking RPC
        #   (2) generate _id beforehand
        Sunny.CRUD[op] = (sig, props) ->
                           sig = Sunny.Utils.toSig(sig)
                           props ?= {}
                           props["_id"] = sig.__meta__.__repr__._makeNewID()
                           Meteor.apply(op, [sig.__meta__.name, props], opts)
      else
        Sunny.CRUD[op] = () -> Meteor.apply(op, arguments, opts) #TODO: callbacks for errors ??

# don't wrap readField
Sunny.CRUD.readField = Sunny._CRUD.readField

# ====================================================================================
#   Register RPC Methods (no stubs)
# ====================================================================================

mthds = {}

if Meteor.isServer
  _wrapForRPC = (op, opFn) ->
    Sunny.Queue.wrapAsInvocation op, () ->
      sdebug "applying Meteor.method '#{op}'"
      opFn.apply(this, arguments)
  mthds[op] = _wrapForRPC op, opFn for op, opFn of Sunny._CRUD
  mthds["event"] = _wrapForRPC "event", (event) ->
    event.setFrom(getSunnyClient(this.connection.id))
    event.setTo(Sunny.myServer())
    event._trigger()

if Meteor.isClient
  mthds[op] = opFn for op, opFn of Sunny._CRUD
  mthds["event"] = (event) -> event._trigger()

Meteor.methods(mthds)


# ====================================================================================
#   Manage publish/subscribe of collections
# ====================================================================================

wrapPublisher = (pub, kls) ->
  connId = pub.connection.id
  pubObjs = kls.__meta__._getPubObjs(connId)

  pub.sunny_added = (name, id, flds) ->
    sdebug ">>>> #{name}(#{id}) added"
    pubObjs[id] = id
    pub.added(name, id, flds)

  pub.sunny_removed = (name, id) ->
    if pubObjs.hasOwnProperty(id)
      sdebug ">>>> #{name}(#{id}) removed"
      delete pubObjs[id]
      pub.removed(name, id)

  pub.sunny_changed = (name, id, flds) ->
    if pubObjs.hasOwnProperty(id)
      sdebug ">>>> #{name}(#{id}) changed: #{Object.keys(flds).join(', ')}"
      pub.changed(name, id, flds)

  pub

Meteor.startup () ->
  if Meteor.isServer
    for klsName, kls of Sunny.Meta.recordsAndMachinesAndBuiltin()
      do (klsName, kls) ->
        meta = kls.__meta__
        col = meta.repr()

        col.allow
          insert: (userId, obj) -> true
          update: (userId, obj, fldNames, mod) -> true
          remove: (userId, obj) -> true

        filterFields = (connId, id, flds) ->
          obj = kls.new(_id: id)
          obj._serFieldsForClient(connId, flds)

        foreachpub = (op, kls, objId, cb) ->
          for connId, pub of meta.__pubs__
            Sunny._currConnId.set(connId)
            try
              cb(connId, pub)
            catch err
              swarn "could not send '#{op}' to client with connId '#{connId}'"

        isInit = true
        handle = col.find({}).observeChanges
          added: (id, flds) ->
            return if isInit
            sdebug "@@@@@@@@@@@ #{klsName}(#{id}) added"
            Sunny.Queue.runAsInvocation "mongo_added", () -> meta.__findDep__.changed()
            foreachpub 'added', kls, id, (connId, pub) ->
              findComp = kls.__meta__._getSigFindComp(connId)
              findComp.addRecords([kls.new(_id: id)])
              # kls._serRecordsForClient(connId, "add", [kls.new(_id: id)])
          removed: (id) ->
            return if isInit
            sdebug "@@@@@@@@@@@ #{klsName}(#{id}) removed"
            meta._deleteObjDeps()
            Sunny.Queue.runAsInvocation "mongo_removed", () -> meta.__findDep__.changed()
            foreachpub 'removed', kls, id, (connId, pub) -> pub.sunny_removed klsName, id
          changed: (id, flds) ->
            return if isInit
            sdebug "@@@@@@@@@@@ #{klsName}(#{id}).#{Object.keys(flds).join(',')} changed"
            Sunny.Queue.runAsInvocation "mongo_changed", () ->
              meta.__findDep__.changed()
              meta._getObjFldDeps(id, fname).changed() for fname, fval of flds
            foreachpub 'changed', kls, id, (connId, pub) ->
              filterFields(connId, id, flds)

        isInit = false

        Meteor.publish klsName, () ->
          self = wrapPublisher(this, kls)
          connId = self.connection.id
          Sunny._currConnId.set(connId)
          meta.__pubs__[connId] = self
          sdebug "SUB '#{klsName}' from #{connId}"

          kls.__meta__._getSigFindComp(connId).setRecords()

          # if Sunny.ACL.applicablePolicies(new OpFind(kls)).length > 0
          #   kls._serRecordsForClient(connId, "set")
          # else
          #   # call `added' for the object currently found in the collection
          #   # slightly faster than the above
          #   h = meta.__repr__.find({}).observeChanges
          #     added: (id, flds) ->
          #       self.sunny_added klsName, id, {}
          #       filterFields(connId, id, flds)
          #   h.stop()

          self.ready()
          self.onStop ()->
            sdebug "UNSUB '#{klsName}' from #{connId}"
            meta._cleanupConn(connId)

  if Meteor.isClient
    for klsName, kls of Sunny.Meta.recordsAndMachinesAndBuiltin()
      do (klsName, kls) ->
        Meteor.subscribe klsName
        console.log "subscribed to #{klsName}"

# ====================================================================================
#   Initializations
# ====================================================================================

Sunny._currClient = new Sunny.Utils.FiberLocalVar("Sunny.currClient")
Sunny._currConnId = new Sunny.Utils.FiberLocalVar("Sunny.currConnId")

# # ----------------------------------------------------------
# # tx initialization
# # ----------------------------------------------------------
# Meteor.startup () ->
#   collectionIndex = {}
#   for name, constr of Sunny.Meta.recordsAndMachinesAndBuiltin()
#     mongoCol = constr.__meta__.__repr__
#     collectionIndex[mongoCol._name] = mongoCol
#   tx.collectionIndex = collectionIndex
#   tx.requireUser = false

# ----------------------------------------------------------
# Client initialization
# ----------------------------------------------------------
if Meteor.isClient
  # augment Meteor.logout to keep track of online clients in SunnyServer
  oldLogoutFn = Meteor.logout
  Meteor.logout = () ->
    oldLogoutFn()
    clnt = Sunny.myClient()
    if clnt
      clnt.user = null
      # Sunny.myServer().onlineClients.remove(clnt)

  # default access denied listener
  Sunny.ACL.onAccessDenied (hash) ->
    alert(hash.msg) if hash.type == "precondition"

# ----------------------------------------------------------
# Server initialization
# ----------------------------------------------------------
if Meteor.isServer
  # delete all Client and Server records and create a single
  # Server record for the currently running server
  Meteor.startup () ->
    slog "destroying all Client records"
    for clnt in Sunny.Meta.clientKls().all()
      _cleanupClient(clnt)
      clnt.destroy()
    srvKls = Sunny.Meta.serverKls()
    Sunny._myServer = switch v = Sunny.Conf.serverRecordPersistence
                        when "reuse"
                          srvs = srvKls.all()
                          if srvs.length > 0 then srvs[0] else srvKls.create()
                        when "create"
                          srvKls.create()
                        when "replace"
                          srvKls.destroyAll()
                          srvKls.create()
                        else
                          sfatal("illegal value for Sunny.Conf.serverRecordPersistence: #{v}")

  # create a Client record whenever a client connects and add it
  # to Server.onlineClients.
  Meteor.onConnection (conn) ->
    server = Sunny.myServer()
    client = Sunny.Meta.clientKls().create(_mConn: conn)
    server.onlineClients.push client
    console.log "client connected: #{conn.id}; total: #{server.onlineClients.length}"

    # destroy and cleanup corresponding Client record when the client disconnects
    conn.onClose () ->
      _cleanupClient(client, conn.id)
      srv = Sunny.myServer()
      srv.onlineClients.remove(client)
      client.destroy()
      console.log "client disconnected: #{conn.id}; left: #{srv.onlineClients.length}"

  # Find/Create corresponding Sunny User and add it to
  # Client.user whenever a user logs in
  Accounts.onLogin (x) ->
    return unless x.allowed
    console.log "on login (#{x.connection.id}): user.id = #{x.user._id}"
    clnt = getSunnyClient(x.connection.id)
    if clnt
      usr = Sunny.Meta.userKls().findOrCreate(x.user)
      clnt.user = usr

  # Reset Client.user whenever login fails
  Accounts.onLoginFailure (x) ->
    console.log "on login failure"
    clnt = getSunnyClient(x.connection.id)
    clnt.user = null if clnt

