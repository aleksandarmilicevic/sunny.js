simport Sunny.Dsl
simport Sunny.Fun
simport Sunny.Types

# ============================ RECORDS ======================================

enums
  Role:     ["Public", "Author", "Reviewer", "PC"]
  PaperTag: ["NeedsReview", "Reviewed", "Accepted"]
  Stage:    ["Submission", "Review", "Rebuttal", "Decision", "Public"]

user(class User)
  
client class Client
  user: User
  role: Role

server class Server
  stage: Stage

record class Review
  author: one User
  body: Text
  score: Int

record class Paper
  title: Text
  authors: set User
  reviewers: set User
  reviews: set Review
  tags: set PaperTag
 
# ============================ EVENTS ======================================


# ============================ Policies ======================================

read_policy Paper.title, (paper) ->
  # titles are visible during the Public stage
  this.server.stage == Staget.Public or
  # titles are always visible to PC, authors, and reviewers
  this.client.role == Role.PC or
  paper.authors.contains(this.client.user) or
  paper.reviewers.contains(this.client.user)

read_policy Paper.authors, (paper, authors) ->
  # visible to all authors
  authors.contains(this.client.user) or
  # after and during the Rebuttal -> visible to PC and reviewers
  (Stage.gte(this.server.stage, Stage.Rebuttal) and
    (paper.reviewers.contains(this.client.user) or this.client.role == Role.PC)) or
  # during Public if accepted -> visible to everyone
  (this.server.stage == Stage.Public and paper.tags.contains(PaperTag.Accepted))

read_policy Paper.reviewers, (paper) ->
  # iff PC
  this.client.role == Role.PC

read_policy Paper.reviews, (paper, reviews) ->
  usr = this.client.user
  # deny before the Review phase
  return false if Stage.lt(this.server.stage, Stage.Review)
  
  if Stage.gt(this.server.stage, Stage.Review)
    # after Review -> visible to PC, authors, reviewers
    return thic.client.role == Role.PC or
           paper.authors.contains(usr) or
           paper.reviewers.contains(usr)
  else
    # during Review phase -> visible to those who have submitted a review already
    return find reviews, (r) -> r.author.equals(usr)
    
    
     
  
