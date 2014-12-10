simport Sunny.Dsl
simport Sunny.Fun
simport Sunny.Types

Sunny.Conf.serverRecordPersistence = 'replace'

# ============================ RECORDS ======================================


user class User
  description: Text
  albums: compose set "Album"
  network: set "Relation"
  pending: set "Relation"
  statusText: () -> this.status || "<statusless>"

record class Relation
  relation_type: Text
  from: User
  to: User
  confirmed: Val

  __static__: {
    getFriends: (user) -> 
      return [] unless user
      user_relations = []
      for relation in Relation.all()
        if relation.to.equals(user) and relation.confirmed is true
          user_relations.push {user: relation.from, relation: relation}
        if relation.from.equals(user) and relation.confirmed is true
          user_relations.push {user: relation.to, relation: relation}
      return user_relations

    getPending: (user) -> 
      return [] unless user
      relations = []
      users = []
      for relation in Relation.all()
        if relation.from.equals(user) and relation.confirmed is false
          relations.push relation
          users.push relation.to
      return [relations, users]

    getRequests: (user) -> 
      return [] unless user
      relations = []
      users = []
      for relation in Relation.all()
        if relation.to.equals(user) and relation.confirmed is false
          relations.push relation
          users.push relation.from
      return [relations, users]

    getOtherFriends: (user) ->
      return [] unless user
      users = User.all()
      friends = []
      friendsArray = Relation.getFriends(user)
      for tuple in friendsArray
        friends.push tuple.user
      requests = Relation.getRequests(user)[1]
      pending = Relation.getPending(user)[1]
      others = []
      for auser in users
        if pending.containsByIdFxn(auser) == false and friends.containsByIdFxn(auser) == false and requests.containsByIdFxn(auser) == false and auser.equals(Sunny.myClient()?.user) == false 
          others.push auser
      return others
      
  }

record class Photo
  title: Text
  link: Text
  time: Val
  tags: compose set Text
  getlink: () ->
    if not this.link
      return "Add Link"
    else
      return this.link
  gettitle: () ->
    if not this.title
      return "Add Title"
    else
      return this.title

record class Album
  name: Text
  owner: User
  photos: compose set Photo
  time: Val

  title: () ->
    if not this.name || this.name.length == 0
      return "untitled"
    else
      return this.name

  __static__: {
    getUserAlbumsById: (userid) -> 
      return [] unless user
      useralbums = []
      albums = Album.all()
      for album in albums
        if album.owner.id() is userid
          useralbums.push album
      return useralbums
  }

        
# ============================ MACHINES ======================================


client class Client
  user: User

server class Server
  albums: compose set Album


# ============================ EVENTS ======================================


event class ClientEvent
  from:
    client: Client
  to:
    server: Server


event class AddPhoto extends ClientEvent
  params:
    album: Album
    photoTitle: Text
    photoLink: Text

  requires: () ->
    return "must log in first!" if not this.client?.user
    return "no album specified" unless this.album
    return "no url given" unless this.photoLink
    return "must ask to view album first." unless this.album.owner.name is this.client.user.name

  ensures: () ->
    photo = Photo.create(
            title: this.photoTitle
            link: this.photoLink
            time: Date.now()
          )
    this.album.photos.push(photo) 
    return photo

event class AddTag extends ClientEvent
  params:
    photo: Photo
    tag: Text

  requires: () ->
    return "must log in first!" if not this.client?.user
    return "no photo specified" unless this.photo
    
  ensures: () ->
    this.photo.tags.push(this.tag) 
    return this.photo

event class RemoveTag extends ClientEvent
  params:
    photo: Photo
    tag: Text

  requires: () ->
    return "must log in first!" if not this.client?.user
    return "no photo specified" unless this.photo
    
  ensures: () ->
    this.photo.tags.remove this.tag
    return this.photo


event class CreateAlbum extends ClientEvent
  params:
    albumTitle: Text
  
  requires: () ->
    return "must log in first" if not this.client?.user
    
  ensures: () ->
    album = Album.create(
      title: "UnTitled"
      time: Date.now()
      owner: this.client.user
      )
    this.client.user.albums.push album
    return album

## relations
event class CreateRelation extends ClientEvent
  params:
    fromU: User
    toU: User
    type: Text
  
  requires: () ->
    return "must log in first" if not this.client?.user
    
  ensures: () ->
    relation = Relation.create(
      from: this.fromU
      to: this.toU
      relation_type: this.type || "Friend"
      confirmed: false
      )
    return relation

event class ConfirmRelation extends ClientEvent
  params:
    relation: Relation
  
  requires: () ->
    return "must log in first" if not this.client?.user
    
  ensures: () ->
    relationObj = Relation.findById(this.relation.id())
    relationObj.confirmed = true
    return relationObj


    
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



 
