UI.registerHelper "salute",     (user) -> user?.name || "<unnamed>"
UI.registerHelper "saluteFull", (user) ->
  return "<anonymous>" unless user
  return "#{user.name} (#{user.email})"

UI.registerHelper "isSelectedEvent", (event) ->
  return event && event.equals(Sunny.myClient()?.selectedEvent)

Sunny.ACL.setAccessDeniedCb (params) ->
  console.log params
  $('#acl-denied').text("Operation #{params.sigName}.#{params.type} denied: #{params.msg}")
  # $('#error-div').show()
  $("#error-div").fadeTo(4000, 500).slideUp(500, ()->)
