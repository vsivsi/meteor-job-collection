############################################################################
#     Copyright (C) 2014 by Vaughn Iverson
#     job-collection is free software released under the MIT/X11 license.
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

validId = (v) ->
  Match.test(v, Match.OneOf(String, Meteor.Collection.ObjectID))

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

clientTestColl = new JobCollection 'ClientTest', { idGeneration: 'MONGO' }
serverTestColl = new JobCollection 'ServerTest', { idGeneration: 'STRING' }
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
    test.ok validId(res), "job.save() failed in callback result"
    q = testColl.processJobs 'testJob', { pollInterval: 250 }, (job, cb) ->
      test.equal job._doc._id, res
      job.done()
      cb()
      q.shutdown () ->
        onComplete()

Tinytest.addAsync 'Job priority is respected', (test, onComplete) ->
  counter = 0
  jobs = []
  jobs[0] = testColl.createJob('testJob', {count: 3}).priority('low')
  jobs[1] = testColl.createJob('testJob', {count: 1}).priority('high')
  jobs[2] = testColl.createJob('testJob', {count: 2})

  jobs[0].save (err, res) ->
    test.fail(err) if err
    test.ok validId(res), "jobs[0].save() failed in callback result"
    jobs[1].save (err, res) ->
      test.fail(err) if err
      test.ok validId(res), "jobs[1].save() failed in callback result"
      jobs[2].save (err, res) ->
        test.fail(err) if err
        test.ok validId(res), "jobs[2].save() failed in callback result"
        q = testColl.processJobs 'testJob', { pollInterval: 250 }, (job, cb) ->
          counter++
          test.equal job.data.count, counter
          job.done()
          cb()
          if counter is 3
            q.shutdown () ->
              onComplete()

Tinytest.addAsync 'A forever retrying job can be scheduled and run', (test, onComplete) ->
  counter = 0
  job = testColl.createJob('testJob', {some: 'data'}).retry({retries: testColl.forever, wait: 0})
  job.save (err, res) ->
    test.fail(err) if err
    test.ok validId(res), "job.save() failed in callback result"
    q = testColl.processJobs 'testJob', { pollInterval: 250 }, (job, cb) ->
      counter++
      test.equal job._doc._id, res
      if counter < 3
        job.fail('Fail test')
        cb()
      else
        job.fail('Fail test', { fatal: true })
        cb()
        q.shutdown () ->
          onComplete()

Tinytest.addAsync 'Retrying job with exponential backoff', (test, onComplete) ->
  counter = 0
  job = testColl.createJob('testJob', {some: 'data'}).retry({retries: 2, wait: 200, backoff: 'exponential'})
  job.save (err, res) ->
    test.fail(err) if err
    test.ok validId(res), "job.save() failed in callback result"
    q = testColl.processJobs 'testJob', { pollInterval: 250 }, (job, cb) ->
      counter++
      test.equal job._doc._id, res
      if counter < 3
        job.fail('Fail test')
        cb()
      else
        job.fail('Fail test')
        cb()
        q.shutdown () ->
          onComplete()

Tinytest.addAsync 'A forever retrying job with "until"', (test, onComplete) ->
  counter = 0
  job = testColl.createJob('testJob', {some: 'data'}).retry({until: new Date(new Date().valueOf() + 1500), wait: 500})
  job.save (err, res) ->
    test.fail(err) if err
    test.ok validId(res), "job.save() failed in callback result"
    q = testColl.processJobs 'testJob', { pollInterval: 250 }, (job, cb) ->
      counter++
      test.equal job._doc._id, res
      job.fail('Fail test')
      cb()
    Meteor.setTimeout(() ->
      job.refresh () ->
        console.log "Until count: #{counter}"
        test.ok job.status is 'failed', "Until didn't cause job to stop retrying"
        q.shutdown () ->
          onComplete()
    ,
      2000
    )
