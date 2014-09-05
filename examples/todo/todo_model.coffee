simport Sunny.Dsl
simport Sunny.Fun
simport Sunny.Types

# ============================ RECORDS ======================================

enums
  View: ['All', 'Active', 'Completed']

record class Task
  desc: Text
  done: Bool

client class Client
  tasks: compose set Task
  showing: View

  isAll:       () -> this.showing == View.All
  isActive:    () -> this.showing == View.Active
  isCompleted: () -> this.showing == View.Completed
  completed:   () -> filter this.tasks, (t) -> t.done == true
  pending:     () -> filter this.tasks, (t) -> t.done == false
  currView:    () ->
    self = this
    if this.isAll()
      Task.all()
    else
      filter Task.all(), (t) -> t.done == self.isCompleted()

# ============================ EVENTS ======================================

event class CreateTask extends SunnyClientEvent
  desc: Text
  ensures: () -> this.client.tasks.push Task.create(desc: this.desc, done: false)

event class ToggleDone extends SunnyClientEvent
  task: Task
  ensures: () -> if this.task.done then this.task.done = false else this.task.done = true

event class SetView extends SunnyClientEvent
  what: View
  ensures: () -> Sunny.myClient()?.showing = View.valueOf(this.what)

event class ClearCompleted extends SunnyClientEvent
  ensures: () -> c.destroy() for c in this.client.completed()

# ============================ Policies ======================================

policy Task,
  find: (tasks) ->
    self = this
    this.allow(filter tasks, (t) -> self.client.tasks.contains(t))
