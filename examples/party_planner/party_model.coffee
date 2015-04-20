simport Sunny.Dsl
simport Sunny.Fun
simport Sunny.Types

# ============================ RECORDS ======================================

user class User
  avatarLink: () -> this.avatar || "https://www.gnu.org/graphics/heckert_gnu.small.png"

record class Party
  name: Text
  location: Text
  time: Val
  hosts: set User
  guests: set User

        
# ============================ MACHINES ======================================


client class Client
  user: User
  selectedEvent: Party


server (class Server)


# ============================ EVENTS ======================================


event class ClientEvent
  from:
    client: Client
  to:
    server: Server

event class SelectEvent extends ClientEvent
  params:
    party: Party

  ensures: () -> this.client.selectedEvent = this.party

event class AddGuestHost extends ClientEvent
  params:
    party: Party
    userName: Text
    user: User
    
  requires: () ->
    return "must specify party" unless this.party
    return "must specify user" unless this.userName || this.user
    unless this.user
      if this.userName.search("@") != -1
        this.user = User.findOne(email: this.userName)
      else
        this.user = User.findOne(name: this.userName)
    return "User #{this.userName} not found" unless this.user

event class AddHost extends AddGuestHost
  requires: () ->
    return "user #{this.user.name} already in the host list" if this.party.hosts.contains(this.user)
  ensures: () ->
    this.party.hosts.push(this.user)

event class AddGuest extends AddGuestHost
  requires: () ->
    return "user #{this.user.name} already in the guest list" if this.party.guests.contains(this.user)
  ensures: () ->
    this.party.guests.push(this.user)


event class RemoveGuestHost extends ClientEvent
  params:
    party: Party
    user: User

  requires: () ->
    return "must specify party" unless this.party
    return "must specify user" unless this.user

event class RemoveHost extends AddGuestHost
  requires: () ->
    return "user #{this.user.name} not in the host list" unless this.party.hosts.contains(this.user)
    return "can't remove last host" if this.party.hosts.length == 1    
  ensures: () ->
    this.party.hosts.remove(this.user)

event class RemoveGuest extends AddGuestHost
  requires: () ->
    return "user #{this.user.name} not in the guest list" unless this.party.guests.contains(this.user)
  ensures: () ->
    this.party.guests.remove(this.user)




            
event class CreateEmptyEvent extends ClientEvent
  requires: () ->
     return "must log in first" unless this.client?.user

  ensures: () ->
     p = Party.create({
       name: "<new event>",
       time: new Date(),
       hosts: [this.client.user],
       guests: []})
     this.client.selectedEvent = p

# ============================ POLICIES ======================================


policy User,
  # user object in question is different from the logged in user
  _precondition: (user) -> not user.equals(this.client?.user)

  read:
    "password": -> return this.deny("can't read User's private data")
    
  update:
    "*": (user, val) -> return this.deny("can't edit other people's data")

policy Party,
  # client user is neither a host nor a guest
  _precondition: (party) ->
    u = this.client?.user
    not (party.hosts.contains(u) || party.guests.contains(u))
     
  read: 
    "name":     -> return this.allow("<private party>")
    "location": -> return this.allow("<secret location>")
    "time":     -> return this.allow("<unknown time>")
    "hosts":    -> return this.allow([])
    "guests":   -> return this.allow([])

policy Party,
  # client user is not a host
  _precondition: (party) -> not party.hosts.contains(this.client?.user)

  pull:
    "guests": (party, elem) ->
       u = this.client?.user
       if u && u.equals(elem)
         return this.allow()
       else
         return this.deny("cannot remove a guest other than you when you are not a host")
    
  update:
    "*": -> return this.deny("cannot update event which you don't host")

# ------------------------------
# stdlib

event class Destroy extends ClientEvent
  params:
    obj: Record

  requires: () ->
    return "must specify object" if not this.obj
    
  ensures: () ->
    this.obj.destroy()



 
