# Template.friend_users.helpers
#   friends: ->
#     return Relation.getFriends(Sunny.myClient()?.user) 
#   currentuser: ->
#   	for user in User.all()
#   		if user._mUser._id is Meteor.user()._id
#   			return user
#   	return null	
#   ifNotCurrentUser: ->
#   	return this._mUser._id isnt Meteor.user()._id	
  	
# Template.requests_users.helpers
#   requests: ->
#   	return Relation.getRequests(Sunny.myClient()?.user)[0]
#   currentuser: ->
#   	for user in User.all()
#   		if user._mUser._id is Meteor.user()._id
#   			return user
#   	return null
#   ifNotCurrentUser: ->
#   	return this._mUser._id isnt Meteor.user()._id	

# Template.other_users.helpers
#   otherfriends: ->
#   	return Relation.getOtherFriends(Sunny.myClient()?.user)
#   pending: ->
#   	return Relation.getPending(Sunny.myClient()?.user)[0]
#   currentuser: ->
#   	for user in User.all()
#   		if user._mUser._id is Meteor.user()._id
#   			return user
#   	return null
#   ifNotCurrentUser: ->
#   	return this._mUser._id isnt Meteor.user()._id	


# Array::containsByIdFxn = (obj) ->
# 	for item in this
#         return true if item.id() == obj.id()
#     false

