############################################################################
#     Copyright (C) 2014 by Vaughn Iverson
#     job-collection is free software released under the MIT/X11 license.
#     See included LICENSE file for details.
############################################################################

#####################################
## Shared between server and client

validNumGTEZero = (v) ->
  Match.test(v, Number) and v >= 0.0

validNumGTZero = (v) ->
  Match.test(v, Number) and v > 0.0

validNumGTEOne = (v) ->
  Match.test(v, Number) and v >= 1.0

validIntGTEZero = (v) ->
  validNumGTEZero(v) and Math.floor(v) is v

validIntGTEOne = (v) ->
  validNumGTEOne(v) and Math.floor(v) is v

validStatus = (v) ->
  Match.test(v, String) and v in Job.jobStatuses

validLogLevel = (v) ->
  Match.test(v, String) and v in Job.jobLogLevels

validRetryBackoff = (v) ->
  Match.test(v, String) and v in Job.jobRetryBackoffMethods

validId = (v) ->
  Match.test(v, Match.OneOf(String, Meteor.Collection.ObjectID))

validLog = () ->
  [{
      time: Date
      runId: Match.OneOf(Match.Where(validId), null)
      level: Match.Where(validLogLevel)
      message: String
  }]

validProgress = () ->
  completed: Match.Where(validNumGTEZero)
  total: Match.Where(validNumGTEZero)
  percent: Match.Where(validNumGTEZero)

validJobDoc = () ->
  _id: Match.Optional Match.OneOf(Match.Where(validId), null)
  runId: Match.OneOf(Match.Where(validId), null)
  type: String
  status: Match.Where validStatus
  data: Object
  result: Match.Optional Object
  priority: Match.Integer
  depends: [ Match.Where(validId) ]
  resolved: [ Match.Where(validId) ]
  after: Date
  updated: Date
  log: Match.Optional validLog()
  progress: validProgress()
  retries: Match.Where validIntGTEZero
  retried: Match.Where validIntGTEZero
  retryUntil: Date
  retryWait: Match.Where validIntGTEZero
  retryBackoff: Match.Where validRetryBackoff
  repeats: Match.Where validIntGTEZero
  repeated: Match.Where validIntGTEZero
  repeatUntil: Date
  repeatWait: Match.Where validIntGTEZero
  created: Date

idsOfDeps = (ids, antecedents, dependents, jobStatuses) ->
  # Cancel the entire tree of antecedents and/or dependents
  # Dependents: jobs that list one of the ids in their depends list
  # Antecedents: jobs with an id listed in the depends list of one of the jobs in ids
  dependsQuery = []
  if dependents
    dependsQuery.push
      depends:
        $elemMatch:
          $in: ids
  if antecedents
    antsArray = []
    @find(
      {
        _id:
          $in: ids
      }
      {
        fields:
          depends: 1
      }
    ).forEach (d) -> antsArray.push(i) for i in d.depends unless i in antsArray
    if antsArray.length > 0
      dependsQuery.push
        _id:
          $in: antsArray
  if dependsQuery
    dependsIds = []
    @find(
      {
        status:
          $in: jobStatuses
        $or: dependsQuery
      }
      {
        fields:
          _id: 1
      }
    ).forEach (d) ->
      dependsIds.push d._id unless d._id in dependsIds
  return dependsIds

rerun_job = (doc, repeats = doc.repeats - 1, wait = doc.repeatWait, repeatUntil = doc.repeatUntil) ->
  # Repeat? if so, make a new job from the old one
  id = doc._id
  runId = doc.runId
  time = new Date()
  delete doc._id
  delete doc.result
  doc.runId = null
  doc.status = "waiting"
  doc.retries = doc.retries + doc.retried
  doc.retries = Job.forever if doc.retries > Job.forever
  doc.retryUntil = repeatUntil
  doc.retried = 0
  doc.repeats = repeats
  doc.repeats = Job.forever if doc.repeats > Job.forever
  doc.repeatUntil = repeatUntil
  doc.repeated = doc.repeated + 1
  doc.updated = time
  doc.created = time
  doc.progress =
    completed: 0
    total: 1
    percent: 0
  doc.log = [
    time: time
    runId: null
    level: 'info'
    message: "Repeating job #{id} from run #{runId}"
  ]
  doc.after = new Date(time.valueOf() + wait)
  if jobId = @insert doc
    return jobId
  else
    console.warn "Job rerun/repeat failed to reschedule!", id, runId
  return null

####################################
# Define Meteor.methods
####################################

serverMethods =
  # Job manager methods

  startJobs: (options) ->
    check options, Match.Optional {}
    options ?= {}
    # The client can't actually do this, so skip it
    if @stopped?
      Meteor.clearTimeout(@stopped) if @stopped and @stopped isnt true
      @stopped = false
    return true

  stopJobs: (options) ->
    check options, Match.Optional
      timeout: Match.Optional(Match.Where validIntGTEOne)
    options ?= {}
    options.timeout ?= 60*1000

    # The client can't actually do any of this, so skip it
    if @stopped?
      Meteor.clearTimeout(@stopped) if @stopped and @stopped isnt true
      @stopped = Meteor.setTimeout(
        () =>
          cursor = @find(
            {
              status: 'running'
            }
          )
          console.warn "Failing #{cursor.count()} jobs on queue stop."
          cursor.forEach (d) => serverMethods.jobFail.bind(@)(d._id, d.runId, "Running at queue stop.")
          if @logStream? # Shutting down closes the logStream!
            @logStream.end()
            @logStream = null
        options.timeout
      )
    return true

  getJob: (ids, options) ->
    check ids, Match.OneOf(Match.Where(validId), [ Match.Where(validId) ])
    check options, Match.Optional
      getLog: Match.Optional Boolean
    options ?= {}
    options.getLog ?= false
    single = false
    if validId(ids)
      ids = [ids]
      single = true
    return null if ids.length is 0
    d = @find(
      {
        _id:
          $in: ids
      }
      {
        fields:
          log: if options.getLog then 1 else 0
      }
    ).fetch()
    if d
      check d, [validJobDoc()]
      if single
        return d[0]
      else
        return d
    return null

  getWork: (type, options) ->
    check type, Match.OneOf String, [ String ]
    check options, Match.Optional
      maxJobs: Match.Optional(Match.Where validIntGTEOne)
    options ?= {}

    # Don't put out any more jobs while shutting down
    if @stopped
      return []

    # Support string types or arrays of string types
    if typeof type is 'string'
      type = [ type ]
    time = new Date()
    ids = @find(
      {
        type:
          $in: type
        status: 'ready'
        runId: null
        after:
          $lte: time
        retries:
          $gt: 0
      }
      {
        sort:
          priority: 1
          retryUntil: 1
          after: 1
        limit: options.maxJobs ? 1
        fields:
          _id: 1
      }).map (d) -> d._id

    if ids?.length
      # This is meteor internal, but it will fail hard if it goes away.
      runId = @_makeNewID()
      num = @update(
        {
          _id:
            $in: ids
          status: 'ready'
          runId: null
          after:
            $lte: time
          retries:
            $gt: 0
        }
        {
          $set:
            status: 'running'
            runId: runId
            updated: time
          $inc:
            retries: -1
            retried: 1
          $push:
            log:
              time: time
              runId: runId
              message: "Job Running"
        }
        {
          multi: true
        }
      )
      if num >= 1
        dd = @find(
          {
            _id:
              $in: ids
            runId: runId
          }
          {
            fields:
              log: 0
          }
        ).fetch()
        if dd?.length
          check dd, [ validJobDoc() ]
          return dd
        else
          console.warn "find after update failed"
      else
        console.warn "Missing running job"
    else
      # console.log "Didn't find a job to process"
    return []

  jobRemove: (ids, options) ->
    check ids, Match.OneOf(Match.Where(validId), [ Match.Where(validId) ])
    check options, Match.Optional {}
    options ?= {}
    if validId(ids)
      ids = [ids]
    return false if ids.length is 0
    num = @remove(
      {
        _id:
          $in: ids
        status:
          $in: Job.jobStatusRemovable
      }
    )
    if num > 0
      console.log "jobRemove succeeded"
      return true
    else
      console.warn "jobRemove failed"
    return false

  jobPause: (ids, options) ->
    check ids, Match.OneOf(Match.Where(validId), [ Match.Where(validId) ])
    check options, Match.Optional {}
    options ?= {}
    if validId(ids)
      ids = [ids]
    return false if ids.length is 0
    time = new Date()
    num = @update(
      {
        _id:
          $in: ids
        status:
          $in: Job.jobStatusPausable
      }
      {
        $set:
          status: "paused"
          updated: time
        $push:
          log:
            time: time
            runId: null
            message: "Job Paused"
      }
      {
        multi: true
      }
    )
    if num > 0
      console.log "jobPause succeeded"
      return true
    else
      console.warn "jobPause failed"
    return false

  jobResume: (ids, options) ->
    check ids, Match.OneOf(Match.Where(validId), [ Match.Where(validId) ])
    check options, Match.Optional {}
    options ?= {}
    if validId(ids)
      ids = [ids]
    return false if ids.length is 0
    time = new Date()
    num = @update(
      {
        _id:
          $in: ids
        status: "paused"
        updated:
          $ne: time
      }
      {
        $set:
          status: "waiting"
          updated: time
        $push:
          log:
            time: time
            runId: null
            message: "Job Resumed"
      }
      {
        multi: true
      }
    )
    if num > 0
      console.log "jobResume succeeded"
      return true
    else
      console.warn "jobResume failed"
    return false

  jobCancel: (ids, options) ->
    check ids, Match.OneOf(Match.Where(validId), [ Match.Where(validId) ])
    check options, Match.Optional
      antecedents: Match.Optional Boolean
      dependents: Match.Optional Boolean
    options ?= {}
    options.antecedents ?= false
    options.dependents ?= true
    if validId(ids)
      ids = [ids]
    return false if ids.length is 0
    time = new Date()
    num = @update(
      {
        _id:
          $in: ids
        status:
          $in: Job.jobStatusCancellable
      }
      {
        $set:
          status: "cancelled"
          runId: null
          progress:
            completed: 0
            total: 1
            percent: 0
          updated: time
        $push:
          log:
            time: time
            runId: null
            level: 'warning'
            message: "Job cancelled"
      }
      {
        multi: true
      }
    )
    # Cancel the entire tree of dependents
    cancelIds = idsOfDeps.bind(@) ids, options.antecedents, options.dependents, Job.jobStatusCancellable

    depsCancelled = false
    if cancelIds.length > 0
      depsCancelled = serverMethods.jobCancel.bind(@)(cancelIds, options)

    if num > 0 or depsCancelled
      console.log "jobCancel succeeded"
      return true
    else
      console.warn "jobCancel failed"
    return false

  jobRestart: (ids, options) ->
    check ids, Match.OneOf(Match.Where(validId), [ Match.Where(validId) ])
    check options, Match.Optional
      retries: Match.Optional(Match.Where validIntGTEOne)
      until: Match.Optional Date
      antecedents: Match.Optional Boolean
      dependents: Match.Optional Boolean
    options ?= {}
    options.retries ?= 1
    options.retries = Job.forever if options.retries > Job.forever
    options.dependents ?= false
    options.antecedents ?= true
    if validId(ids)
      ids = [ids]
    return false if ids.length is 0
    console.log "Restarting: #{ids}"
    time = new Date()

    query =
      _id:
        $in: ids
      status:
        $in: Job.jobStatusRestartable

    mods =
      $set:
        status: "waiting"
        progress:
          completed: 0
          total: 1
          percent: 0
        updated: time
      $inc:
        retries: options.retries
      $push:
        log:
          time: time
          runId: null
          level: 'info'
          message: "Job Restarted"

    if options.until?
      mods.$set.retryUntil = options.until

    num = @update query, mods, {multi: true}

    # Restart the entire tree of dependents
    restartIds = idsOfDeps.bind(@) ids, options.antecedents, options.dependents, Job.jobStatusRestartable

    depsRestarted = false
    if restartIds.length > 0
      depsRestarted = serverMethods.jobRestart.bind(@)(restartIds, options)

    if num > 0 or depsRestarted
      console.log "jobRestart succeeded"
      return true
    else
      console.warn "jobRestart failed"
    return false

  # Job creator methods

  jobSave: (doc, options) ->
    check doc, validJobDoc()
    check options, Match.Optional
      cancelRepeats: Match.Optional Boolean
    check doc.status, Match.Where (v) ->
      Match.test(v, String) and v in [ 'waiting', 'paused' ]
    options ?= {}
    options.cancelRepeats ?= false
    doc.repeats = Job.forever if doc.repeats > Job.forever
    doc.retries = Job.forever if doc.retries > Job.forever

    time = new Date()

    # This enables the default case of "run immediately" to
    # not be impacted by a client's clock
    doc.after = time if doc.after < time
    doc.retryUntil = time if doc.retryUntil < time
    doc.repeatUntil = time if doc.repeatUntil < time

    if doc._id
      num = @update(
        {
          _id: doc._id
          status: 'paused'
          runId: null
        }
        {
          $set:
            status: 'waiting'
            data: doc.data
            retries: doc.retries
            retryUntil: doc.retryUntil
            retryWait: doc.retryWait
            retryBackoff: doc.retryBackoff
            repeats: doc.repeats
            repeatUntil: doc.repeatUntil
            repeatWait: doc.repeatWait
            depends: doc.depends
            priority: doc.priority
            after: doc.after
            updated: time
          $push:
            log:
              time: time
              runId: null
              level: 'info'
              message: 'Job Resubmitted'
        }
      )
      if num
        return doc._id
      else
        return null
    else
      if doc.repeats is Job.forever and options.cancelRepeats
        # If this is unlimited repeating job, then cancel any existing jobs of the same type
        @find(
          {
            type: doc.type
            status:
              $in: Job.jobStatusCancellable
          }
        ).forEach (d) => serverMethods.jobCancel.bind(@)(d._id, {})
      doc.created = time
      doc.log.push
        time: time
        runId: null
        level: 'info'
        message: "Job Submitted"

      return @insert doc

  # Worker methods

  jobProgress: (id, runId, completed, total, options) ->
    check id, Match.Where(validId)
    check runId, Match.Where(validId)
    check completed, Match.Where validNumGTEZero
    check total, Match.Where validNumGTZero
    check options, Match.Optional {}
    options ?= {}

    # Notify the worker to stop running if we are shutting down
    if @stopped
      return null

    progress =
      completed: completed
      total: total
      percent: 100*completed/total

    check progress, Match.Where (v) ->
      v.total >= v.completed and 0 <= v.percent <= 100

    time = new Date()
    console.log "Updating progress", id, runId, progress
    num = @update(
      {
        _id: id
        runId: runId
        status: "running"
      }
      {
        $set:
          progress: progress
          updated: time
      }
    )
    if num is 1
      console.log "jobProgress succeeded", progress
      return true
    else
      console.warn "jobProgress failed"
    return false

  jobLog: (id, runId, message, options) ->
    check id, Match.Where(validId)
    check runId, Match.Where(validId)
    check message, String
    check options, Match.Optional
      level: Match.Optional(Match.Where validLogLevel)
    options ?= {}
    time = new Date()
    num = @update(
      {
        _id: id
      }
      {
        $push:
          log:
            time: time
            runId: runId
            level: options.level ? 'info'
            message: message
        $set:
          updated: time
      }
    )
    if num is 1
      return true
    else
      console.warn "jobLog failed"
    return false

  jobRerun: (id, options) ->
    check id, Match.Where(validId)
    check options, Match.Optional
      repeats: Match.Optional(Match.Where validIntGTEZero)
      until: Match.Optional Date
      wait: Match.Optional(Match.Where validIntGTEZero)

    doc = @findOne(
      {
        _id: id
        status: "completed"
      }
      {
        fields:
          log: 0
          progress: 0
          updated: 0
          after: 0
          status: 0
      }
    )

    if doc?
      options ?= {}
      options.repeats ?= 0
      options.repeats = Job.forever if options.repeats > Job.forever
      options.until ?= doc.repeatUntil
      options.wait ?= 0
      return rerun_job.bind(@) doc, options.repeats, options.wait, options.until

    return false

  jobDone: (id, runId, result, options) ->
    check id, Match.Where(validId)
    check runId, Match.Where(validId)
    check result, Object
    check options, Match.Optional {}
    options ?= {}
    time = new Date()
    doc = @findOne(
      {
        _id: id
        runId: runId
        status: "running"
      }
      {
        fields:
          log: 0
          progress: 0
          updated: 0
          after: 0
          status: 0
      }
    )
    unless doc?
      console.warn "Running job not found", id, runId
      return false
    num = @update(
      {
        _id: id
        runId: runId
        status: "running"
      }
      {
        $set:
          status: "completed"
          result: result
          progress:
            completed: 1
            total: 1
            percent: 100
          updated: time
        $push:
          log:
            time: time
            runId: runId
            message: "Job Completed Successfully"
      }
    )
    if num is 1
      if doc.repeats > 0 and doc.repeatUntil - doc.repeatWait >= time
        jobId = rerun_job.bind(@) doc

      # Resolve depends
      n = @update(
        {
          depends:
            $all: [ id ]
        }
        {
          $pull:
            depends: id
          $push:
            resolved: id
            log:
              time: time
              runId: null
              level: 'info'
              message: "Dependency resolved for #{id} by #{runId}"
        }
      )
      console.log "Job #{id} Resolved #{n} depends"
      console.log "jobDone succeeded"
      return true
    else
      console.warn "jobDone failed"
    return false

  jobFail: (id, runId, err, options) ->
    check id, Match.Where(validId)
    check runId, Match.Where(validId)
    check err, String
    check options, Match.Optional
      fatal: Match.Optional Boolean

    options ?= {}
    options.fatal ?= false

    time = new Date()
    doc = @findOne(
      {
        _id: id
        runId: runId
        status: "running"
      }
      {
        fields:
          log: 0
          progress: 0
          updated: 0
          after: 0
          runId: 0
          status: 0
      }
    )
    unless doc?
      console.warn "Running job not found", id, runId
      return false

    after = switch doc.retryBackoff
      when 'exponential'
        new Date(time.valueOf() + doc.retryWait*Math.pow(2, doc.retried-1))
      else
        new Date(time.valueOf() + doc.retryWait)  # 'constant'

    newStatus = if (not options.fatal and
                    doc.retries > 0 and
                    doc.retryUntil >= after) then "waiting" else "failed"

    num = @update(
      {
        _id: id
        runId: runId
        status: "running" }
      {
        $set:
          status: newStatus
          runId: null
          after: after
          progress:
            completed: 0
            total: 1
            percent: 0
          updated: time
        $push:
          log:
            time: time
            runId: runId
            level: if newStatus is 'failed' then 'danger' else 'warning'
            message: "Job Failed with #{"Fatal" if options.fatal} Error: #{err}"
      }
    )
    if newStatus is "failed" and num is 1
      # Cancel any dependent jobs too
      @find(
        {
          depends:
            $all: [ id ]
        }
      ).forEach (d) => serverMethods.jobCancel.bind(@)(d._id)
    if num is 1
      console.log "jobFail succeeded"
      return true
    else
      console.warn "jobFail failed"
    return false

# Share these methods so they'll be available on server and client

share.serverMethods = serverMethods
