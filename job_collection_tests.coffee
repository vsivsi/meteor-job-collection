############################################################################
#     Copyright (C) 2014 by Vaughn Iverson
#     jobCollection is free software released under the MIT/X11 license.
#     See included LICENSE file for details.
############################################################################

bind_env = (func) ->
  if Meteor.isServer and typeof func is 'function'
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

  clientTestColl.allow
    admin: () -> true

  Tinytest.add 'Set permissions to allow admin on ClientTest', (test) ->
    test.equal clientTestColl.allows.admin[0](), true

  Tinytest.add 'Set polliing interval', (test) ->
    interval = clientTestColl.interval
    clientTestColl.promote 250
    test.notEqual interval, clientTestColl.interval, "clientTestColl interval not updated"
    interval = serverTestColl.interval
    serverTestColl.promote 250
    test.notEqual interval, serverTestColl.interval, "serverTestColl interval not updated"

testColl = if Meteor.isClient then clientTestColl else serverTestColl

Tinytest.addAsync 'Run startJobs on new job collection', (test, onComplete) ->
  testColl.startJobs (err, res) ->
    test.fail(err) if err
    test.equal res, true, "startJobs failed in callback result"
    if Meteor.isServer
      test.equal testColl.stopped, false, "startJobs didn't start job collection"
    onComplete()

Tinytest.addAsync 'Create a job and see that it is added to the collection and runs', (test, onComplete) ->
  job = testColl.createJob 'testJob', { some: 'data' }
  job.save (err, res) ->
    test.fail(err) if err
    test.instanceOf res, Meteor.Collection.ObjectID , "job.save() failed in callback result"
    q = testColl.processJobs 'testJob', { pollInterval: 250 }, (job, cb) ->
      console.log "In worker"
      test.equal job._doc._id, res
      console.log "Before callback"
      cb()
      console.log "After callback"
      q.shutdown () ->
        console.warn "Shutdown complete..."
        onComplete()
