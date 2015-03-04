simport Sunny.Dsl
simport Sunny.Fun
simport Sunny.Types

Sunny.Conf.serverRecordPersistence = 'replace'

### RECORD ###

user class User
  birthdate: Val

# name not empty
# administrator not empty
# name unique globally
record class Team
  name: Text
  administrator: User
  members: set User

# name not empty
# name unique for run
# team not empty
record class CompetitionEntry
  name: Text
  team: Team
  participants: set User

### SERVICES ###

server class Server
  teams: set Team
  competition_entries: set CompetitionEntry

client class Client
  user: User

### EVENTS ###

event class ClientEvent
  from:
    client: Client
  to:
    server: Server

event class CreateTeam extends ClientEvent
  params:
    name: Text

  requires: () ->
    return "must log in first!" if not this.client?.user
    return "no name given" unless this.name

  ensures: () ->
    team = Team.create(
	     name: this.name 
	     administrator: this.client.user
           )
    team.members.push team.administrator
    this.server.teams.push team    
    return team

event class CreateCompetitionEntry extends ClientEvent
  params:
    name: Text
    team: Team

  requires: () ->
    return "must log in first!" if not this.client?.user
    return "no name given" unless this.name
    return "no team given" unless this.team
    return "not administrator of team" unless this.client.user.equals this.team.administrator
    return "team not registered" unless this.server.teams.contains this.team

  ensures: () ->
    competition_entry = CompetitionEntry.create(
	                  name: this.name 
	                  team: this.team
                        )
    competition_entry.participants.push this.client.user
    this.server.competition_entries.push competition_entry
    return competition_entry

event class CreateMembership extends ClientEvent
  params:
    user: User
    team: Team
    
  requires: () ->
    return "must log in first!" if not this.client?.user
    return "not administrator of team" unless this.client.user.equals this.team.administrator
    return "already member of team" if this.team.members.contains this.user

  ensures: () ->
    this.team.members.push user

event class CreateParticipation extends ClientEvent
  params:
    user: User
    competition_entry: CompetitionEntry

  requires: () ->
    return "must log in first!" if not this.client?.user
    return "not administrator of team" unless this.client.user.equals this.team.administrator    
    return "competition entry not registered" unless this.server.competition_entries.contains this.competition_entry
    return "already a participant" if this.competition_entry.participants.contains this.user

  ensures: () ->
    this.competition_entry.participants.push this.user

### POLICIES ###

policy User,
  _precondition: (user) -> not user.equals(this.client?.user)

  read:
    "! name": -> return this.deny("can't read user's private data")
    
  update:
    "*": (user, val) -> return this.deny("can't edit other users' data")

#policy Team,
#  _precondition: (team) -> not team.administrator?.equals(this.client?.user)
#
#  read:
#    "! name, administrator, members": -> return this.deny("can't read team's private data")
#
#  update:
#    "*": (team, val) -> return this.deny("can't edit non-administered team's data")

#policy CompetitionEntry,
#  _precondition: (competition_entry) -> not competition_entry.team?.administrator?.equals(this.client?.user)
#
#  update:
#    "*": (competition_entry, val) -> return this.deny("can't edit non-administered competition entry's data")

### STDLIB ###

event class Destroy extends ClientEvent
  params:
    obj: Record

  requires: () ->
    return "must specify object" unless this.obj
    
  ensures: () ->
    this.obj.destroy()
