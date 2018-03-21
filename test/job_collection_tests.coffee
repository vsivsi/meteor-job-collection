assert = require('chai').assert;

############################################################################
#     Copyright (C) 2014-2017 by Vaughn Iverson
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

validJobDoc = (d) ->
  Match.test(d, defaultColl.jobDocPattern)

it 'JobCollection constructs the object correctly', () ->
  assert.instanceOf defaultColl, JobCollection, "JobCollection constructor failed"
  assert.equal defaultColl.root, 'queue', "default root isn't 'queue'"
  if Meteor.isServer
    assert.equal defaultColl.stopped, true, "isn't initially stopped"
    assert.equal defaultColl.logStream, null, "Doesn't have a logStream"
    assert.instanceOf defaultColl.allows, Object, "allows isn't an object"
    assert.equal Object.keys(defaultColl.allows).length, 22, "allows not properly initialized"
    assert.instanceOf defaultColl.denys, Object, "denys isn't an object"
    assert.equal Object.keys(defaultColl.denys).length, 22, "denys not properly initialized"
  else
    assert.equal defaultColl.logConsole, false, "Doesn't have a logConsole"

clientTestColl = new JobCollection 'ClientTest', { idGeneration: 'MONGO' }
serverTestColl = new JobCollection 'ServerTest', { idGeneration: 'STRING' }

# The line below is a regression test for issue #51
dummyTestColl = new JobCollection 'DummyTest', { idGeneration: 'STRING' }

if Meteor.isServer
  remoteTestColl = new JobCollection 'RemoteTest', { idGeneration: 'STRING' }
  remoteTestColl.allow
    admin: () -> true
else
  remoteConnection = DDP.connect Meteor.absoluteUrl()
  remoteServerTestColl = new JobCollection 'RemoteTest', { idGeneration: 'STRING', connection: remoteConnection }

testColl = null  # This will be defined differently for client / server

if Meteor.isServer

  clientTestColl.allow
    admin: () -> true

  it 'Set permissions to allow admin on ClientTest', () ->
    assert.equal clientTestColl.allows.admin[0](), true

  it 'Set polling interval', () ->
    interval = clientTestColl.interval
    clientTestColl.promote 250
    assert.notEqual interval, clientTestColl.interval, "clientTestColl interval not updated"
    interval = serverTestColl.interval
    serverTestColl.promote 250
    assert.notEqual interval, serverTestColl.interval, "serverTestColl interval not updated"

testColl = if Meteor.isClient then clientTestColl else serverTestColl

# it 'Run startJobs on new job collection', (onComplete) ->
#   testColl.startJobs (err, res) ->
#     assert.fail(err) if err
#     assert.equal res, true, "startJobs failed in callback result"
#     if Meteor.isServer
#       assert.equal testColl.stopped, false, "startJobs didn't start job collection"
#     onComplete()

it 'Run startJobServer on new job collection', (onComplete) ->
  testColl.startJobServer (err, res) ->
    assert.fail(err) if err
    assert.equal res, true, "startJobServer failed in callback result"
    if Meteor.isServer
      assert.equal testColl.stopped, false, "startJobServer didn't start job collection"
    onComplete()

if Meteor.isServer

  it 'Create a server-side job and see that it is added to the collection and runs', (onComplete) ->
    jobType = "TestJob_#{Math.round(Math.random()*1000000000)}"
    job = new Job testColl, jobType, { some: 'data' }
    assert.ok validJobDoc(job.doc)
    res = job.save()
    assert.ok validId(res), "job.save() failed in sync result"
    q = testColl.processJobs jobType, { pollInterval: 250 }, (job, cb) ->
      assert.equal job._doc._id, res
      job.done()
      cb()
    ev = testColl.events.once 'jobDone', (msg) ->
      assert.equal msg.method, 'jobDone'
      if msg.params[0] is res
        q.shutdown { level: 'soft', quiet: true }, () ->
          onComplete()

it 'Create a job and see that it is added to the collection and runs', (onComplete) ->
  jobType = "TestJob_#{Math.round(Math.random()*1000000000)}"
  job = new Job testColl, jobType, { some: 'data' }
  assert.ok validJobDoc(job.doc)
  job.save (err, res) ->
    assert.fail(err) if err
    assert.ok validId(res), "job.save() failed in callback result"
    q = testColl.processJobs jobType, { pollInterval: 250 }, (job, cb) ->
      assert.equal job._doc._id, res
      job.done()
      cb()
      q.shutdown { level: 'soft', quiet: true }, () ->
        onComplete()

it 'Create an invalid job and see that errors correctly propagate', (onComplete) ->
  console.warn "****************************************************************************************************"
  console.warn "***** The following exception dump is a Normal and Expected part of error handling unit tests: *****"
  console.warn "****************************************************************************************************"
  jobType = "TestJob_#{Math.round(Math.random()*1000000000)}"
  job = new Job testColl, jobType, { some: 'data' }
  delete job.doc.status
  assert.equal validJobDoc(job.doc), false
  if Meteor.isServer
    eventFlag = false
    err = null
    ev = testColl.events.once 'jobSave', (msg) ->
      eventFlag = true
      assert.fail(new Error "Server error event didn't dispatch") unless msg.error
    try
      job.save()
    catch e
      err = e
    finally
      assert.ok eventFlag
      assert.fail(new Error "Server exception wasn't thrown") unless err
      onComplete()
  else
    job.save (err, res) ->
      assert.fail(new Error "Error did not propagate to Client") unless err
      onComplete()

it 'Create a job and then make a new doc with its document', (onComplete) ->
  jobType = "TestJob_#{Math.round(Math.random()*1000000000)}"
  job2 = new Job testColl, jobType, { some: 'data' }
  if Meteor.isServer
    job = new Job 'ServerTest', job2.doc
  else
    job = new Job 'ClientTest', job2.doc
  assert.ok validJobDoc(job.doc)
  job.save (err, res) ->
    assert.fail(err) if err
    assert.ok validId(res), "job.save() failed in callback result"
    q = testColl.processJobs jobType, { pollInterval: 250 }, (job, cb) ->
      assert.equal job._doc._id, res
      job.done()
      cb()
      q.shutdown { level: 'soft', quiet: true }, () ->
        onComplete()

it 'A repeating job that returns the _id of the next job', (onComplete) ->
  counter = 0
  jobType = "TestJob_#{Math.round(Math.random()*1000000000)}"
  job = new Job(testColl, jobType, {some: 'data'}).repeat({ repeats: 1, wait: 250 })
  job.save (err, res) ->
    assert.fail(err) if err
    assert.ok validId(res), "job.save() failed in callback result"
    q = testColl.processJobs jobType, { pollInterval: 250 }, (job, cb) ->
      counter++
      if counter is 1
        assert.equal job.doc._id, res
        job.done "Result1", { repeatId: true }, (err, res) ->
          assert.fail(err) if err
          assert.ok res?
          assert.notEqual res, true
          testColl.getJob res, (err, j) ->
            assert.fail(err) if err
            assert.equal j._doc._id, res
            cb()
      else
        assert.notEqual job.doc._id, res
        job.done "Result2", { repeatId: true }, (err, res) ->
          assert.fail(err) if err
          assert.equal res, true
          cb()
          q.shutdown { level: 'soft', quiet: true }, () ->
            onComplete()

it 'Dependent jobs run in the correct order', (onComplete) ->
  jobType = "TestJob_#{Math.round(Math.random()*1000000000)}"
  job = new Job testColl, jobType, { order: 1 }
  job2 = new Job testColl, jobType, { order: 2 }
  job.delay 1000 # Ensure that job 1 has the opportunity to run first
  job.save (err, res) ->
    assert.fail(err) if err
    assert.ok validId(res), "job.save() failed in callback result"
    job2.depends [job]
    job2.save (err, res) ->
      assert.fail(err) if err
      assert.ok validId(res), "job.save() failed in callback result"
      count = 0
      q = testColl.processJobs jobType, { pollInterval: 250 }, (job, cb) ->
        count++
        assert.equal count, job.data.order
        job.done()
        cb()
        if count is 2
          q.shutdown { level: 'soft', quiet: true }, () ->
            onComplete()

if Meteor.isServer
  it 'Dry run of dependency check returns status object', (onComplete) ->
    jobType = "TestJob_#{Math.round(Math.random()*1000000000)}"
    job = new Job testColl, jobType, { order: 1 }
    job2 = new Job testColl, jobType, { order: 2 }
    job3 = new Job testColl, jobType, { order: 3 }
    job4 = new Job testColl, jobType, { order: 4 }
    job5 = new Job testColl, jobType, { order: 5 }
    job.save()
    job2.save()
    job3.save()
    job4.save()
    job5.depends [job, job2, job3, job4]
    job5.save (err, res) ->
      assert.fail(err) if err
      assert.ok validId(res), "job2.save() failed in callback result"
      # This creates an inconsistent state
      testColl.update { _id: job.doc._id, status: 'ready' }, { $set: { status: 'cancelled' }}
      testColl.update { _id: job2.doc._id, status: 'ready' }, { $set: { status: 'failed' }}
      testColl.update { _id: job3.doc._id, status: 'ready' }, { $set: { status: 'completed' }}
      testColl.remove { _id: job4.doc._id }
      dryRunRes = testColl._checkDeps job5.doc
      assert.equal dryRunRes.cancelled.length, 1
      assert.equal dryRunRes.cancelled[0], job.doc._id
      assert.equal dryRunRes.failed.length, 1
      assert.equal dryRunRes.failed[0], job2.doc._id
      assert.equal dryRunRes.resolved.length, 1
      assert.equal dryRunRes.resolved[0], job3.doc._id
      assert.equal dryRunRes.removed.length, 1
      assert.equal dryRunRes.removed[0], job4.doc._id
      onComplete()

it 'Dependent job saved after completion of antecedent still runs', (onComplete) ->
  jobType = "TestJob_#{Math.round(Math.random()*1000000000)}"
  job = new Job testColl, jobType, { order: 1 }
  job2 = new Job testColl, jobType, { order: 2 }
  job.save (err, res) ->
    assert.fail(err) if err
    assert.ok validId(res), "job.save() failed in callback result"
    job2.depends [job]
    count = 0
    q = testColl.processJobs jobType, { pollInterval: 250 }, (j, cb) ->
      count++
      j.done "Job #{j.data.order} Done", (err, res) ->
        assert.fail(err) if err
        assert.ok res
        if j.data.order is 1
          job2.save (err, res) ->
            assert.fail(err) if err
            assert.ok validId(res), "job2.save() failed in callback result"
        else
          q.shutdown { level: 'soft', quiet: true }, () ->
            onComplete()
      cb()

it 'Dependent job saved after failure of antecedent is cancelled', (onComplete) ->
  jobType = "TestJob_#{Math.round(Math.random()*1000000000)}"
  job = new Job testColl, jobType, { order: 1 }
  job2 = new Job testColl, jobType, { order: 2 }
  job.save (err, res) ->
    assert.fail(err) if err
    assert.ok validId(res), "job.save() failed in callback result"
    job2.depends [job]
    q = testColl.processJobs jobType, { pollInterval: 250 }, (j, cb) ->
      j.fail "Job #{j.data.order} Failed", (err, res) ->
        assert.fail(err) if err
        assert.ok res
        job2.save (err, res) ->
          assert.fail(err) if err
          assert.isNull res, "job2.save() failed in callback result"
          q.shutdown { level: 'soft', quiet: true }, () ->
            onComplete()
      cb()

it 'Dependent job saved after cancelled antecedent is also cancelled', (onComplete) ->
  jobType = "TestJob_#{Math.round(Math.random()*1000000000)}"
  job = new Job testColl, jobType, { order: 1 }
  job2 = new Job testColl, jobType, { order: 2 }
  job.save (err, res) ->
    assert.fail(err) if err
    assert.ok validId(res), "job.save() failed in callback result"
    job2.depends [job]
    job.cancel (err, res) ->
      assert.fail(err) if err
      assert.ok res
      job2.save (err, res) ->
        assert.fail(err) if err
        assert.isNull res, "job2.save() failed in callback result"
        onComplete()

it 'Dependent job saved after removed antecedent is cancelled', (onComplete) ->
  jobType = "TestJob_#{Math.round(Math.random()*1000000000)}"
  job = new Job testColl, jobType, { order: 1 }
  job2 = new Job testColl, jobType, { order: 2 }
  job.save (err, res) ->
    assert.fail(err) if err
    assert.ok validId(res), "job.save() failed in callback result"
    job2.depends [job]
    job.cancel (err, res) ->
      assert.fail(err) if err
      assert.ok res
      job.remove (err, res) ->
        assert.fail(err) if err
        assert.ok res
        job2.save (err, res) ->
          assert.fail(err) if err
          assert.isNull res, "job2.save() failed in callback result"
          onComplete()

it 'Cancel succeeds for job without deps, with using option dependents: false', (onComplete) ->
  jobType = "TestJob_#{Math.round(Math.random()*1000000000)}"
  job = new Job testColl, jobType, {}
  job.save (err, res) ->
    assert.fail(err) if err
    assert.ok validId(res), "job.save() failed in callback result"
    job.cancel { dependents: false }, (err, res) ->
       assert.fail(err) if err
       assert.ok res
       onComplete()

it 'Dependent job with delayDeps is delayed', (onComplete) ->
  @timeout 10000
  jobType = "TestJob_#{Math.round(Math.random()*1000000000)}"
  job = new Job testColl, jobType, { order: 1 }
  job2 = new Job testColl, jobType, { order: 2 }
  job.delay 1000 # Ensure that job2 has the opportunity to run first
  job.save (err, res) ->
    assert.fail(err) if err
    assert.ok validId(res), "job.save() failed in callback result"
    job2.depends [job]
    job2.save (err, res) ->
      assert.fail(err) if err
      assert.ok validId(res), "job.save() failed in callback result"
      count = 0
      q = testColl.processJobs jobType, { pollInterval: 250 }, (job, cb) ->
        count++
        assert.equal count, job.data.order
        timer = new Date()
        job.done(null, { delayDeps: 1500 })
        cb()
        if count is 2
          console.log "#{(new Date()).valueOf()} is greater than"
          console.log "#{timer.valueOf() + 1500}"
          assert.ok (new Date()).valueOf() > timer.valueOf() + 1500
          q.shutdown { level: 'soft', quiet: true }, () ->
            onComplete()

it 'Job priority is respected', (onComplete) ->
  counter = 0
  jobType = "TestJob_#{Math.round(Math.random()*1000000000)}"
  jobs = []
  jobs[0] = new Job(testColl, jobType, {count: 3}).priority('low')
  jobs[1] = new Job(testColl, jobType, {count: 1}).priority('high')
  jobs[2] = new Job(testColl, jobType, {count: 2})

  jobs[0].save (err, res) ->
    assert.fail(err) if err
    assert.ok validId(res), "jobs[0].save() failed in callback result"
    jobs[1].save (err, res) ->
      assert.fail(err) if err
      assert.ok validId(res), "jobs[1].save() failed in callback result"
      jobs[2].save (err, res) ->
        assert.fail(err) if err
        assert.ok validId(res), "jobs[2].save() failed in callback result"
        q = testColl.processJobs jobType, { pollInterval: 250 }, (job, cb) ->
          counter++
          assert.equal job.data.count, counter
          job.done()
          cb()
          if counter is 3
            q.shutdown { level: 'soft', quiet: true }, () ->
              onComplete()

it 'A forever retrying job can be scheduled and run', (onComplete) ->
  counter = 0
  jobType = "TestJob_#{Math.round(Math.random()*1000000000)}"
  job = new Job(testColl, jobType, {some: 'data'}).retry({retries: testColl.forever, wait: 0})
  job.save (err, res) ->
    assert.fail(err) if err
    assert.ok validId(res), "job.save() failed in callback result"
    q = testColl.processJobs jobType, { pollInterval: 250 }, (job, cb) ->
      counter++
      assert.equal job.doc._id, res
      if counter < 3
        job.fail('Fail test')
        cb()
      else
        job.fail('Fail test', { fatal: true })
        cb()
        q.shutdown { level: 'soft', quiet: true }, () ->
          onComplete()

it 'Retrying job with exponential backoff', (onComplete) ->
  counter = 0
  jobType = "TestJob_#{Math.round(Math.random()*1000000000)}"
  job = new Job(testColl, jobType, {some: 'data'}).retry({retries: 2, wait: 200, backoff: 'exponential'})
  job.save (err, res) ->
    assert.fail(err) if err
    assert.ok validId(res), "job.save() failed in callback result"
    q = testColl.processJobs jobType, { pollInterval: 250 }, (job, cb) ->
      counter++
      assert.equal job.doc._id, res
      if counter < 3
        job.fail('Fail test')
        cb()
      else
        job.fail('Fail test')
        cb()
        q.shutdown { level: 'soft', quiet: true }, () ->
          onComplete()

it 'A forever retrying job with "until"', (onComplete) ->
  @timeout 10000
  counter = 0
  jobType = "TestJob_#{Math.round(Math.random()*1000000000)}"
  job = new Job(testColl, jobType, {some: 'data'}).retry({until: new Date(new Date().valueOf() + 1500), wait: 500})
  job.save (err, res) ->
    assert.fail(err) if err
    assert.ok validId(res), "job.save() failed in callback result"
    q = testColl.processJobs jobType, { pollInterval: 250 }, (job, cb) ->
      counter++
      assert.equal job.doc._id, res
      job.fail('Fail test')
      cb()
    Meteor.setTimeout(() ->
      job.refresh () ->
        assert.equal job._doc.status, 'failed', "Until didn't cause job to stop retrying"
        q.shutdown { level: 'soft', quiet: true }, () ->
          onComplete()
    ,
      2500
    )

it 'Autofail and retry a job', (onComplete) ->
  @timeout 10000
  counter = 0
  jobType = "TestJob_#{Math.round(Math.random()*1000000000)}"
  job = new Job(testColl, jobType, {some: 'data'}).retry({retries: 2, wait: 0})
  job.save (err, res) ->
    assert.fail(err) if err
    assert.ok validId(res), "job.save() failed in callback result"
    q = testColl.processJobs jobType, { pollInterval: 250, workTimeout: 500 }, (job, cb) ->
      counter++
      assert.equal job.doc._id, res
      if counter is 2
        job.done('Success')
      # Will be called without done/fail on first attempt
      cb()

    Meteor.setTimeout(() ->
      job.refresh () ->
        assert.equal job._doc.status, 'completed', "Job didn't successfully autofail and retry"
        q.shutdown { level: 'soft', quiet: true }, () ->
          onComplete()
    ,
      2500
    )

if Meteor.isServer

  it 'Save, cancel, restart, refresh: retries are correct.', (onComplete) ->
    jobType = "TestJob_#{Math.round(Math.random()*1000000000)}"
    j = new Job(testColl, jobType, { foo: "bar" })
    j.save()
    j.cancel()
    j.restart({ retries: 0 })
    j.refresh()
    assert.equal j._doc.repeatRetries, j._doc.retries + j._doc.retried
    onComplete()

  it 'Add, cancel and remove a large number of jobs', (onComplete) ->
    c = count = 500
    jobType = "TestJob_#{Math.round(Math.random()*1000000000)}"
    for i in [1..count]
      j = new Job(testColl, jobType, { idx: i })
      j.save (err, res) ->
        assert.fail(err) if err
        assert.fail("job.save() Invalid _id value returned") unless validId(res)
        c--
        unless c
          ids = testColl.find({ type: jobType, status: 'ready'}).map((d) -> d._id)
          assert.equal count, ids.length
          testColl.cancelJobs ids, (err, res) ->
            assert.fail(err) if err
            assert.fail("cancelJobs Failed") unless res
            ids = testColl.find({ type: jobType, status: 'cancelled'}).map((d) -> d._id)
            assert.equal count, ids.length
            testColl.removeJobs ids, (err, res) ->
              assert.fail(err) if err
              assert.fail("removeJobs Failed") unless res
              ids = testColl.find { type: jobType }
              assert.equal 0, ids.count()
              onComplete()

  it 'A forever repeating job with "schedule" and "until"', (onComplete) ->
    @timeout 10000
    counter = 0
    jobType = "TestJob_#{Math.round(Math.random()*1000000000)}"
    job = new Job(testColl, jobType, {some: 'data'})
      .repeat({
        until: new Date(new Date().valueOf() + 3500),
        schedule: testColl.later.parse.text("every 1 second")})
      .delay(1000)
    job.save (err, res) ->
      assert.fail(err) if err
      assert.ok validId(res), "job.save() failed in callback result"
      q = testColl.processJobs jobType, { pollInterval: 250 }, (job, cb) ->
        counter++
        if counter is 1
          assert.equal job.doc._id, res
        else
          assert.notEqual job.doc._id, res
        job.done({}, { repeatId: true })
        cb()
      listener = (msg) ->
        if counter is 2
          job.refresh () ->
            assert.equal job._doc.status, 'completed'
            q.shutdown { level: 'soft', quiet: true }, () ->
              ev.removeListener 'jobDone', listener
              onComplete()
      ev = testColl.events.on 'jobDone', listener

# it 'Run stopJobs on the job collection', (onComplete) ->
#   testColl.stopJobs { timeout: 1 }, (err, res) ->
#     assert.fail(err) if err
#     assert.equal res, true, "stopJobs failed in callback result"
#     if Meteor.isServer
#       assert.notEqual testColl.stopped, false, "stopJobs didn't stop job collection"
#     onComplete()

it 'Run shutdownJobServer on the job collection', (onComplete) ->
  testColl.shutdownJobServer { timeout: 1 }, (err, res) ->
    assert.fail(err) if err
    assert.equal res, true, "shutdownJobServer failed in callback result"
    if Meteor.isServer
      assert.notEqual testColl.stopped, false, "shutdownJobServer didn't stop job collection"
    onComplete()

if Meteor.isClient

  it 'Run startJobServer on remote job collection', (onComplete) ->
    remoteServerTestColl.startJobServer (err, res) ->
      assert.fail(err) if err
      assert.equal res, true, "startJobServer failed in callback result"
      onComplete()

  it 'Create a job and see that it is added to a remote server collection and runs', (onComplete) ->
    jobType = "TestJob_#{Math.round(Math.random()*1000000000)}"
    job = new Job remoteServerTestColl, jobType, { some: 'data' }
    assert.ok validJobDoc(job.doc)
    job.save (err, res) ->
      assert.fail(err) if err
      assert.ok validId(res), "job.save() failed in callback result"
      q = remoteServerTestColl.processJobs jobType, { pollInterval: 250 }, (job, cb) ->
        assert.equal job._doc._id, res
        job.done()
        cb()
        q.shutdown { level: 'soft', quiet: true }, () ->
          onComplete()

  it 'Run shutdownJobServer on remote job collection', (onComplete) ->
    remoteServerTestColl.shutdownJobServer { timeout: 1 }, (err, res) ->
      assert.fail(err) if err
      assert.equal res, true, "shutdownJobServer failed in callback result"
      onComplete()
