simport Sunny.Dsl
simport Sunny.Fun
simport Sunny.Types

# Sunny.Conf.serverRecordPersistence = 'replace'
Sunny.Conf.deepPolicyChecking = false
Sunny.Conf.atomicity = 'none'

# ============================ RECORDS ======================================

user class User
  status: Text

  statusText: () -> this.status || "<statusless>"

record class Msg
  text: Text
  sender: User
  time: Val

record class ChatRoom
  name: Text
  members: set User
  messages: compose set Msg

  title: () ->
    if not this.name || this.name.length == 0
      return "unnamed"
    else
      return this.name

        
# ============================ MACHINES ======================================


client class Client
  user: User
  selectedRooms: set ChatRoom

server class Server
  rooms: compose set ChatRoom


# ============================ EVENTS ======================================


event class ClientEvent
  from:
    client: Client
  to:
    server: Server

event class AddRoomToSelected extends ClientEvent
  params: room: ChatRoom
  requires: () -> return "must specify room" unless this.client && this.room
  ensures: () ->
    this.client.selectedRooms.push(this.room)

event class RemoveRoomFromSelected extends ClientEvent
  params: room: ChatRoom
  requires: () -> return "must specify room" unless this.client && this.room
  ensures: () ->
    this.client.selectedRooms.remove(this.room)
    
event class SendMsg extends ClientEvent
  params:
    room: ChatRoom
    msgText: Text

  requires: () ->
    return "must log in first!" if not this.client?.user
    return "no room given" unless this.room
    return "no text given" unless this.msgText
    return "must join room first" unless this.room.members.contains(this.client.user)

  ensures: () ->
    msg = Msg.create(
            sender: this.client.user
            text: this.msgText
            time: Date.now()
          )
    this.room.messages.push(msg)
    return msg


event class CreateRoom extends ClientEvent
  params:
    roomName: Text

  requires: () ->
    return "must log in first" if not this.client?.user
    
  ensures: () ->
    room = ChatRoom.create(name: this.roomName)
    room.members.push this.client.user
    this.server.rooms.push room
    return room

event class JoinRoom extends ClientEvent
  params:
    room: ChatRoom

  requires: () ->
    return "must specify room" unless this.room
    return "must log in" unless this.client?.user
    return "must not already be a member" if this.room.members.contains this.client.user
    
  ensures: () ->
    this.room.members.push this.client.user


event class LeaveRoom extends ClientEvent
  params:
    room: ChatRoom

  requires: () ->
    return "must specify room" unless this.room
    return "must log in"       unless this.client?.user
    return "must be a member"  unless this.room.members.contains this.client.user
    
  ensures: () ->
    this.room.members.remove this.client.user

    
# ============================ POLICIES ======================================

policy User,
  _precondition: (user) -> not user.equals(this.client?.user)

  read:   "! name, avatar, status": -> return this.deny("can't read User's private data")
  update: "*":  (user, val) -> return this.deny("can't edit other people's data")
  delete:       (user)      -> return this.deny("can't delete other user")
  find:         (users) ->
    client = this.client
    return this.allow(filter users, (u) -> u.equals(client.user) || u.status != "busy")
  
policy Client,
  _precondition: (clnt) -> clnt.user && !clnt.user.equals(this.client?.user)
  update:   "*": (clnt) -> return this.deny()
  delete:        (clnt) -> return this.deny()

# show messages starting with "#private" only to members
policy ChatRoom,
  read:
    messages: (room, msgs) ->
      return this.deny() if not this.client?.user
      if room.members.contains this.client?.user
        return this.allow()
      else
        return this.allow(filter msgs, (m) -> not /\#private\b/.test(m.text))

policy Msg,
  _precondition: (msg) -> not (msg.sender && msg.sender.equals(this.client?.user))
  update: "*": () -> return this.deny("can't change other's messages")
  delete:      () -> return this.deny("can't delete other's messages")

# ------------------------------
# stdlib

event class Destroy extends ClientEvent
  params:
    obj: Record

  requires: () ->
    return "must specify object" if not this.obj
    
  ensures: () ->
    this.obj.destroy()


# =======================================

Sunny.methods
  createNewRoom: (name) ->
    sdebug "createNewRoom calleD"
    sdebug "my client: #{Sunny.myClient()}"    
    ev = Sunny.CreateRoom.new(roomName: name)
    sdebug "event's client: #{ev.client}"
    ev.trigger()

  sendMessageToRoom: (name, text) ->
    sdebug "**** BBBBBBBB"
    sdebug "**** name: #{name}, text: #{text}"
    sdebug "**** my client: #{Sunny.myClient().user}"
    myRoom = App.ChatRoom.findOne({name: name})
    sdebug "**** myRoom: #{myRoom}"
    #ev = App.JoinRoom.new(room: myRoom)
    #ev.trigger()
    #sdebug "CCCCC"
    ev = App.SendMsg.new(room: myRoom, msgText: text)
    ev.trigger()
    sdebug "DDDDDD"
    #msg = {text: text, sender: null, time: new Date()}
    #App.Msg.__meta__.__repr__.insert(msg)
