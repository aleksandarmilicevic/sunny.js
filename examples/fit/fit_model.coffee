simport Sunny.Dsl
simport Sunny.Fun
simport Sunny.Types

# ============================ RECORDS ======================================

enums
  ActivityKind: ['Walking', 'Running', 'Biking', 'Swimming', 'Lifting']

record class Point
  time      : DateTime
  heartRate : Int
  power     : Int
  gpsLong   : Real
  gpsLat    : Real

record class Activity
  kind      : ActivityKind
  date      : DateTime
  mDuration : Int # in minutes
  mDistance : Int # in meters
  points    : compose set Point

user class User
  kgWeight   : Real # in kilograms
  cmHeight   : Real # in centimeters
  age        : Int  # in years
  activities : compose set Activity
  daylyGoals : [ActivityKind, Int] # duration in minutes per activity kind

client class Client
  user: User

# ============================ EVENTS ======================================

event class ClientEvent
  from:
    client: Client

event class LoggedInUserEvent extends ClientEvent
  requires: () ->
    return "must log in first" unless this.client?.user
      

event class UpdateUser extends LoggedInUserEvent
  params:
    weight: Real
    height: Real
    age   : Int

  ensures: () ->
    this.client.user.kgWeight = this.weight
    this.client.user.cmHeight = this.height
    this.client.user.age = this.age
        
  
event class AddActivity extends LoggedInUserEvent
  params:
    kind: ActivityKind
    date: DateTime
    time: DateTime
    duration: Int
    distance: Int
    
  ensures: () ->
    act = this.client.user.activities.push Activity.create(
            kind: this.kind
            date: this.date
            mDuration: this.duration
            mDistance: this.distance)


# ============================ Policies ======================================



UI.registerHelper "salute", (user) -> user?.name || "<unnamed>"
UI.registerHelper "formatTodayDate", () ->
    d = Date.now()
    "#{d.getMonth()}/#{d.getDate()}/#{d.getYear()}"
UI.registerHelper "isLoggedInUser", (user) ->
    lUser = Sunny.myClient()?.user
    lUser && lUser.email == user?.email    
