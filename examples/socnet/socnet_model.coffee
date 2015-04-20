simport Sunny.Dsl
simport Sunny.Fun
simport Sunny.Types

# ============================ RECORDS ======================================

user class User
  status: Text
  location: Text
  network: [Text, "User"]
  wall: set "Post"

  avatarLink: () -> this.avatar || "https://www.gnu.org/graphics/heckert_gnu.small.png"
  statusText: () -> this.status || "<statusless>"

  addRelationship: (kind, user) ->
    this.network.push [kind, user]

  hasConnection: (user) ->
    findIndex(this.network, (e) -> e[1].equals(user)) != -1
    
  friendshipKinds: (user) ->
    kinds = findFirst this.network.groupByRange(), (e) -> e.key.equals(user)
    return [] unless kinds
    return map kinds.value, (e) -> e[0]

record class Chunk
  isText:    () -> false
  isHashTag: () -> false
  isUserTag: () -> false

record class TextChunk extends Chunk
  text: Text
  isText: () -> true

record class HashTagChunk extends Chunk
  tag: Text
  isHashTag: () -> true

record class UserTagChunk extends Chunk
  user: User
  isUserTag: () -> true

record class Post
  text: Text
  author: User
  body: compose set Chunk
  time: Val

  timeFormatted: () ->
    options = {
        weekday: "long", year: "numeric", month: "short",
        day: "numeric", hour: "2-digit", minute: "2-digit"
    }
    this.time.toLocaleTimeString("en-us", options)

        
# ============================ MACHINES ======================================


client class Client
  user: User
  selectedUser: User

  selectedUserOrMe: () -> this.selectedUser || this.user

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
    userName: Text

  requires: () ->
    return "must log in first!" unless this.client?.user
    return "must specify user" unless (this.user || this.userName)
    unless this.user
      if this.userName.search("@") != -1
        this.user = User.findOne(email: this.userName)
      else
        this.user = User.findOne(name: this.userName)
      return "User #{this.userName} not found" unless this.user

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

event class SelectUser extends ClientEvent
  params:
    user: User
  
  requires: () ->
    return "must log in first!" unless this.client?.user
    return "must specify user" unless this.user

  ensures: () ->
    this.client.selectedUser = this.user

event class PostEvent extends ClientEvent
  params:
    to: User
    text: Text

  requires: () ->
    return "must log in first!" unless this.client?.user
    return "must specify user" unless this.to
    return "must specify text" unless this.text

  ensures: () ->
    body = []
    pos = 0
    re = /#\w+|@\w+/gm
    match = re.exec(this.text)
    while match
      if match.index > pos
        body.push TextChunk.create(text: this.text.substring(pos, match.index))
      tag = match[0]
      if tag.charAt(0) == '#'
        body.push HashTagChunk.create(tag: tag)
      else
        u = User.findOne({name: tag.substring(1)})
        if u
          body.push UserTagChunk.create({user: u})
        else
          body.push TextChunk.create({text: tag})            
      pos = match.index + tag.length
      match = re.exec(this.text)
    if this.text.length > pos
      body.push TextChunk.create(text: this.text.substring(pos))

    p = Post.create({
          author: this.client.user,
          text: this.text,
          body: body,
          time: new Date()
        })
    this.to.wall.push(p)


# ============================ POLICIES ======================================


policy User,
  # user object in question is different from the logged in user
  _precondition: (user) -> not user.equals(this.client?.user)

  read:
    "password": -> return this.deny("can't read User's private data")
    
  update:
    "! wall": (user, val) -> return this.deny("can't edit other people's data")

policy Post,
  # post in question has author different from the logged in user
  _precondition: (post) -> not post.author.equals(this.client?.user)

  delete: (post) -> return this.deny("cannot delete someone else's post")


# ==============================================================================
# Ivan's policies
# ==============================================================================
policy User,
  # user object in question is "Ivan" and is different from the logged in user
  _precondition: (user) -> (not user.equals(this.client?.user)) and user.email == "ivan@mit.edu"

  # hide friendship kinds
  read:
    "network": (user) -> return this.allow(user.network.groupByRange().map((e) -> ["", e.key]))


# ==============================================================================
# Eunsuk's policies
# ==============================================================================
policy Post,
  find: (posts) ->
    self = this
    hidePost = (post) ->
      post.author?.email == "eskang@mit.edu" and
      post.text.search("#fucker") != -1 and
      post.author.friendshipKinds(self.client.user).contains("boss")
    return this.allow(filter posts, (p) -> !hidePost(p))

# ==============================================================================
# Aleks's policies
# ==============================================================================
policy User,
  # user object in question is "Aleks" and is different from the logged in user
  _precondition: (user) -> (not user.equals(this.client?.user)) and user.email == "aleks@mit.edu"

  # don't let people see my network
  read:
    "network": -> return this.allow([])
    
  # don't allow people to post on my wall
  update:
    "wall": (user) -> return this.deny("DON'T POST ON ALEKS' WALL!!!")



# ------------------------------
# stdlib

event class Destroy extends ClientEvent
  params:
    obj: Record

  requires: () ->
    return "must specify object" if not this.obj
    
  ensures: () ->
    this.obj.destroy()



 
