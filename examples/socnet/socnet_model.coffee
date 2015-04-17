simport Sunny.Dsl
simport Sunny.Fun
simport Sunny.Types

# ============================ RECORDS ======================================

user class User
  status: Text
  location: Text
  network: [Text, "User"]
  wall: set "Post"

  statusText: () -> this.status || "<statusless>"

  addRelationship: (kind, user) ->
    this.network.push [kind, user]    
    # rel = findFirst this.network, (r) -> r.kind = kind
    # if not rel
    #   rel = Relationship.create({kind: kind, users: []})
    #   this.network.push(rel)
    # rel.users.push(user)

  # networkGroupedByKind: () ->
  #   grp = {}
  #   kinds = []
  #   for r in this.network
  #     if not grp[r.kind]
  #       grp[r.kind] = []
  #       kinds.push(r.kind)
  #     grp[r.kind].push(r)
  #   ans = []
  #   for k in kinds
  #     ans.push {kind: k, rels: grp[k]}
  #   return ans

  

record class Relationship
  kind: Text
  users: set User

record class Post
  text: Text
  author: User
  tags: set Text
  time: Val

        
# ============================ MACHINES ======================================


client class Client
  user: User

server (class Server)


# ============================ EVENTS ======================================


event class ClientEvent
  from:
    client: Client
  to:
    server: Server

event class AddToMyNetwork extends ClientEvent
  params:
    kind: Text
    user: User

  requires: () ->
    return "must log in first!" unless this.client?.user
    return "must specify kind" unless this.kind

  ensures: () ->
    me = this.client.user
    kind = this.kind || "other"
    me.addRelationship(kind, this.user)

event class RemoveMyRel extends ClientEvent
  params:
    kind: Text
    user: User
    
  requires: () ->
    return "must log in first!" unless this.client?.user
    return "must specify kind" unless this.kind
    return "must specify user" unless this.user

  ensures: () ->
    me = this.client.user
    me.network.remove([this.kind, this.user])
        
# ============================ POLICIES ======================================


# policy User,
#   _precondition: (user) -> not user.equals(this.client?.user)

#   read:
#     "! name, status": -> return this.deny("can't read User's private data")
    
#   update:
#     "*": (user, val) -> return this.deny("can't edit other people's data")

# policy Client,
#   _precondition: (clnt) -> not clnt.equals(this.client)

#   read:
#     user: (clnt, user) ->
#        if clnt?.user?.status == "busy"
#          return this.deny()
#        else
#          return this.allow()

# # show messages starting with "#private" only to members
# policy ChatRoom,
#   read:
#     messages: (room, msgs) ->
#       return this.deny() if not this.client?.user
#       if room.members.contains this.client?.user
#         return this.allow()
#       else
#         return this.allow(filter msgs, (m) -> not /\#private\b/.test(m.text))




# ------------------------------
# stdlib

event class Destroy extends ClientEvent
  params:
    obj: Record

  requires: () ->
    return "must specify object" if not this.obj
    
  ensures: () ->
    this.obj.destroy()



 
