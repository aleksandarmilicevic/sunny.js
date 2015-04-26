simport Sunny.Dsl
simport Sunny.Fun
simport Sunny.Types

# ============================ RECORDS ======================================

record class Party
  name: Text
  location: Text
  time: Val
  finalized: Bool
  hosts: set SunnyUser
  guests: set SunnyUser
        
# ============================ MACHINES ======================================

client class Client
  user: SunnyUser
  selectedEvent: Party

# ============================ EVENTS ======================================

event class ClientEvent
  from:
    client: Client
  to:
    server: SunnyServer

event class SelectEvent extends ClientEvent
  params:
    party: Party
  ensures: () -> this.client.selectedEvent = this.party

event class ToggleFinalized extends ClientEvent
  params:
    party: Party

  requires: () -> return "must specify party" unless this.party
  ensures: () -> this.party.finalized = not this.party.finalized

event class AddGuestHost extends ClientEvent
  params:
    party: Party
    userName: Text
    user: SunnyUser
    
  requires: () ->
    return "must specify party" unless this.party
    return "must specify user" unless this.userName || this.user
    unless this.user
      if this.userName.search("@") != -1
        this.user = SunnyUser.findOne(email: this.userName)
      else
        this.user = SunnyUser.findOne(name: this.userName)
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
    user: SunnyUser

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


policy SunnyUser,
  # user object in question is different from the logged in user
  _precondition: (user) -> not user.equals(this.client?.user)

  read:
    "password": -> return this.deny("can't read User's private data")
    
  update:
    "*": (user, val) -> return this.deny("can't edit other people's data")

# policy Party,
#   # client user is neither a host nor a guest OR
#   # client is a guest but party hasn't been finalized
#   _precondition: (party) ->
#     u = this.client?.user
#     hosts = party.hosts
#     guests = party.guests
#     (!hosts.contains(u) && !guests.contains(u)) or
#     (guests.contains(u) && !party.finalized)
     
#   read: 
#     "name":     -> return this.allow("<private party>")
#     "location": -> return this.allow("<secret location>")
#     "time":     -> return this.allow("<unknown time>")
#     "hosts":    -> return this.allow([])
#     "guests":   -> return this.allow([])

policy Party,
  # client user is neither a host nor a guest ==> can't see name, location, time
  _precondition: (party) ->
    u = this.client?.user
    !party.hosts.contains(u) && !party.guests.contains(u)
     
  read: 
    "name":      () -> return this.allow("<private party>")
    "location":  () -> return this.allow("<secret location>")
    "time":      () -> return this.allow("<unknown time>")
    "finalized": () -> return this.allow(false)
    "hosts":     () -> return this.allow([])
    "guests":    () -> return this.allow([])
    
policy Party,
  # client user is not a host and the party hasn't been finalized
  _precondition: (party) ->
    !party.hosts.contains(this.client?.user) && !party.finalized
     
  read:
    "hosts":  () -> return this.allow([])
    "guests": () -> return this.allow([])

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
    
  update: "*": -> return this.deny("cannot update event which you don't host")
  delete:      -> return this.deny("cannot delete event which you don't host")

# ------------------------------
# stdlib

event class Destroy extends ClientEvent
  params:
    obj: Record

  requires: () ->
    return "must specify object" if not this.obj
    
  ensures: () ->
    this.obj.destroy()



 
