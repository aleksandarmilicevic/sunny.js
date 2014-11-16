UI.registerHelper "salute",     (user) -> user?.name || "<unnamed>"
UI.registerHelper "saluteFull", (user) ->
  return "<anonymous>" unless user
  return "#{user.name} (#{user.email})"
