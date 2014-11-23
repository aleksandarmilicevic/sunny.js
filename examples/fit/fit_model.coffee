simport Sunny.Dsl
simport Sunny.Fun
simport Sunny.Types

# ============================ RECORDS ======================================

# enums
#   ActivityKind: ['Walking', 'Running', 'Biking']

# record class Segment
#   time      : Date
#   heartRate : Int
#   power     : Int
#   gpsLong   : Real
#   gpsLat    : Real

# record class Activity
#   kind      : ActivityKind
#   date      : Date
#   mDuration : Int # in minutes
#   segments  : compose set Segment

user class User
  xxx: Text
  # kgWeight   : Real # in kilograms
  # cmHeight   : Real # in centimeters
  # activities : compose set Activity
  # daylyGoals : [ActivityKind, Int] # duration in minutes per activity kind

client class Client
  user: User

# ============================ EVENTS ======================================

# ============================ Policies ======================================


