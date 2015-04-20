isInMyNetwork = (user) ->
  me = Sunny.myClient()?.user
  return false unless me
  return true if me.equals(user)
  return some me.network, (kindUserTuple) -> kindUserTuple[1].equals(user)

UI.registerHelper "salute",     (user) -> user?.name || "<unnamed>"
UI.registerHelper "saluteFull", (user) ->
  return "<anonymous>" unless user
  return "#{user.name} (#{user.email})"

UI.registerHelper "isInMyNetwork", isInMyNetwork
UI.registerHelper "isNotInMyNetwork", (user) -> !isInMyNetwork(user)


Sunny.ACL.setAccessDeniedCb (params) ->
  console.log params
  $('#acl-denied').text("Operation #{params.sigName}.#{params.type} denied: #{params.msg}")
  # $('#error-div').show()
  $("#error-div").fadeTo(4000, 500).slideUp(500, ()->)
