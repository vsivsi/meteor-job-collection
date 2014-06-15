############################################################################
#     Copyright (C) 2014 by Vaughn Iverson
#     jobCollection is free software released under the MIT/X11 license.
#     See included LICENSE file for details.
############################################################################

bind_env = (func) ->
  if typeof func is 'function'
    return Meteor.bindEnvironment func, (err) -> throw err
  else
    return func

subWrapper = (sub, func) ->
  (test, onComplete) ->
    if Meteor.isClient
      Deps.autorun () ->
        if sub.ready()
          func test, onComplete
    else
      func test, onComplete

defaultColl = new JobCollection()

Tinytest.add 'JobCollection default constructor', (test) ->
  test.instanceOf defaultColl, JobCollection, "JobCollection constructor failed"
  test.equal defaultColl.root, 'queue', "default root isn't 'queue'"
  if Meteor.isServer
    test.equal defaultColl.stopped, true, "isn't initially stopped"
    test.equal defaultColl.logStream, null, "Doesn't have a logStream"
    test.instanceOf defaultColl.allows, Object, "allows isn't an object"
    test.equal Object.keys(defaultColl.allows).length, 19, "allows not properly initialized"
    test.instanceOf defaultColl.denys, Object, "denys isn't an object"
    test.equal Object.keys(defaultColl.denys).length, 19, "denys not properly initialized"
  else
    test.equal defaultColl.logConsole, false, "Doesn't have a logConsole"

clientTestColl = new JobCollection 'ClientTest'
serverTestColl = new JobCollection 'ServerTest'
testColl = null  # This will be defined differently for client / server

if Meteor.isServer
  Tinytest.add 'Set polliing interval', (test) ->
    clientTestColl.promote 250
    serverTestColl.promote 250

testColl = if Meteor.isClient then clientTestColl else serverTestColl

Tinytest.add 'Run startJob on new job collection', (test) ->
