simport Sunny.Dsl
simport Sunny.Fun
simport Sunny.Types

Sunny.Conf.serverRecordPersistence = 'replace'

# ============================ RECORDS ======================================

user class User
  # status: Text
  # statusText: () -> this.status || "...statusless..."
  salute: () -> "hello #{this.name}"

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

server class Server
  rooms: compose set ChatRoom


# ============================ EVENTS ======================================


event class ClientEvent
  from:
    client: Client
  to:
    server: Server


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

# policy User,
#   update:
#     "*": (user, val) ->
#       return this.allow() if user.equals(this.client?.user)
#       return this.deny("can't edit other people's data")

#   read:
#     status: (user, status) ->
#       return this.allow() if user.equals(this.client?.user)
#       self = this
#       if this.server.rooms.some((room) -> room.members.containsAll([user, self.client.user]))
#         return this.allow()
#       else
#         return this.deny()

# policy Client,
#   read:
#     user: (clnt, user) ->
#       return this.allow() if clnt.equals(this.client)
#       if user?.status == "busy"
#         return this.deny()
#       else
#         return this.allow()

























# ------------------------------
# stdlib

event class Destroy extends ClientEvent
  params:
    obj: Record

  requires: () ->
    return "must specify object" if not this.obj
    
  ensures: () ->
    this.obj.destroy()


Sunny.methods
  createNewRoom: (name) ->
    sdebug "createNewRoom calleD"
    sdebug "my client: #{Sunny.myClient()}"    
    ev = Sunny.CreateRoom.new(roomName: name)
    sdebug "event's client: #{ev.client}"
    ev.trigger()
 
