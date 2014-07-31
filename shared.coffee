############################################################################
#     Copyright (C) 2014 by Vaughn Iverson
#     jobCollection is free software released under the MIT/X11 license.
#     See included LICENSE file for details.
############################################################################

_validNumGTEZero = (v) ->
  Match.test(v, Number) and v >= 0.0

_validNumGTZero = (v) ->
  Match.test(v, Number) and v > 0.0

_validNumGTEOne = (v) ->
  Match.test(v, Number) and v >= 1.0

_validIntGTEZero = (v) ->
  _validNumGTEZero(v) and Math.floor(v) is v

_validIntGTEOne = (v) ->
  _validNumGTEOne(v) and Math.floor(v) is v

_validStatus = (v) ->
  Match.test(v, String) and v in Job.jobStatuses

_validLogLevel = (v) ->
  Match.test(v, String) and v in Job.jobLogLevels

_validRetryBackoff = (v) ->
  Match.test(v, String) and v in Job.jobRetryBackoffMethods

_validId = (v) ->
  Match.test(v, Match.OneOf(String, Meteor.Collection.ObjectID))

_validLog = () ->
  [{
      time: Date
      runId: Match.OneOf(Match.Where(_validId), null)
      level: Match.Where(_validLogLevel)
      message: String
  }]

_validProgress = () ->
  completed: Match.Where(_validNumGTEZero)
  total: Match.Where(_validNumGTEZero)
  percent: Match.Where(_validNumGTEZero)

_validJobDoc = () ->
  _id: Match.Optional Match.OneOf(Match.Where(_validId), null)
  runId: Match.OneOf(Match.Where(_validId), null)
  type: String
  status: Match.Where _validStatus
  data: Object
  result: Match.Optional Object
  failures: Match.Optional [ Object ]
  priority: Match.Integer
  depends: [ Match.Where(_validId) ]
  resolved: [ Match.Where(_validId) ]
  after: Date
  updated: Date
  log: Match.Optional _validLog()
  progress: _validProgress()
  retries: Match.Where _validIntGTEZero
  retried: Match.Where _validIntGTEZero
  retryUntil: Date
  retryWait: Match.Where _validIntGTEZero
  retryBackoff: Match.Where _validRetryBackoff
  repeats: Match.Where _validIntGTEZero
  repeated: Match.Where _validIntGTEZero
  repeatUntil: Date
  repeatWait: Match.Where _validIntGTEZero
  created: Date


class JobCollectionBase extends Meteor.Collection

  constructor: (@root = 'queue', options = {}) ->
    unless @ instanceof JobCollectionBase
      return new JobCollectionBase(@root, options)

    options.idGeneration ?= 'STRING'  # or 'MONGO'
    options.noCollectionSuffix ?= false

    collectionName = @root

    unless options.noCollectionSuffix
      collectionName += '.jobs'

    # Call super's constructor
    super collectionName, { idGeneration: options.idGeneration }

  jobLogLevels: Job.jobLogLevels
  jobPriorities: Job.jobPriorities
  jobStatuses: Job.jobPriorities
  jobStatusCancellable: Job.jobStatusCancellable
  jobStatusPausable: Job.jobStatusPausable
  jobStatusRemovable: Job.jobStatusRemovable
  jobStatusRestartable: Job.jobStatusRestartable
  forever: Job.forever
  foreverDate: Job.foreverDate

  ddpMethods: Job.ddpMethods
  ddpPermissionLevels: Job.ddpPermissionLevels
  ddpMethodPermissions: Job.ddpMethodPermissions

  createJob: (params...) -> new Job @root, params...
  processJobs: (params...) -> new Job.processJobs @root, params...
  getJob: (params...) -> Job.getJob @root, params...
  getWork: (params...) -> Job.getWork @root, params...
  startJobs: (params...) -> Job.startJobs @root, params...
  stopJobs: (params...) -> Job.stopJobs @root, params...
  makeJob: (params...) -> Job.makeJob @root, params...
  getJobs: (params...) -> Job.getJobs @root, params...
  cancelJobs: (params...) -> Job.cancelJobs @root, params...
  pauseJobs: (params...) -> Job.pauseJobs @root, params...
  resumeJobs: (params...) -> Job.resumeJobs @root, params...
  restartJobs: (params...) -> Job.restartJobs @root, params...
  removeJobs: (params...) -> Job.removeJobs @root, params...

  _generateMethods: () ->
    methodsOut = {}
    methodPrefix = '_DDPMethod_'
    for methodName, methodFunc of @ when methodName[0...methodPrefix.length] is methodPrefix
      baseMethodName = methodName[methodPrefix.length..]
      methodsOut["#{@root}_#{baseMethodName}"] = @_methodWrapper(baseMethodName, methodFunc.bind(@))
    return methodsOut

  _idsOfDeps: (ids, antecedents, dependents, jobStatuses) ->
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

  _rerun_job: (doc, repeats = doc.repeats - 1, wait = doc.repeatWait, repeatUntil = doc.repeatUntil) ->
    # Repeat? if so, make a new job from the old one
    id = doc._id
    runId = doc.runId
    time = new Date()
    delete doc._id
    delete doc.result
    doc.runId = null
    doc.status = "waiting"
    doc.retries = doc.retries + doc.retried
    doc.retries = @forever if doc.retries > @forever
    doc.retryUntil = repeatUntil
    doc.retried = 0
    doc.repeats = repeats
    doc.repeats = @forever if doc.repeats > @forever
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
      @_promote_jobs? [jobId]
      return jobId
    else
      console.warn "Job rerun/repeat failed to reschedule!", id, runId
    return null

  _DDPMethod_startJobs: (options) ->
    check options, Match.Optional {}
    options ?= {}
    # The client can't actually do this, so skip it
    if @stopped?
      Meteor.clearTimeout(@stopped) if @stopped and @stopped isnt true
      @stopped = false
    return true

  _DDPMethod_stopJobs: (options) ->
    check options, Match.Optional
      timeout: Match.Optional(Match.Where _validIntGTEOne)
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
          cursor.forEach (d) => @_DDPMethod_jobFail d._id, d.runId, "Running at queue stop."
          if @logStream? # Shutting down closes the logStream!
            @logStream.end()
            @logStream = null
        options.timeout
      )
    return true

  _DDPMethod_getJob: (ids, options) ->
    check ids, Match.OneOf(Match.Where(_validId), [ Match.Where(_validId) ])
    check options, Match.Optional
      getLog: Match.Optional Boolean
      getFailures: Match.Optional Boolean
    options ?= {}
    options.getLog ?= false
    options.getFailures ?= false
    single = false
    if _validId(ids)
      ids = [ids]
      single = true
    return null if ids.length is 0
    docs = @find(
      {
        _id:
          $in: ids
      }
      {
        fields:
          log: if options.getLog then 1 else 0
          failures: if options.getFailures then 1 else 0
          _private: 0
      }
    ).fetch()
    if docs?.length
      if scrub?
        docs = @scrub d for d in docs
      check docs, [_validJobDoc()]
      if single
        return docs[0]
      else
        return docs
    return null

  _DDPMethod_getWork: (type, options) ->
    check type, Match.OneOf String, [ String ]
    check options, Match.Optional
      maxJobs: Match.Optional(Match.Where _validIntGTEOne)
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
        docs = @find(
          {
            _id:
              $in: ids
            runId: runId
          }
          {
            fields:
              log: 0
              failures: 0
              _private: 0
          }
        ).fetch()
        if docs?.length
          if scrub?
            docs = @scrub d for d in docs
          check docs, [ _validJobDoc() ]
          return docs
        else
          console.warn "find after update failed"
      else
        console.warn "Missing running job"
    else
      # console.log "Didn't find a job to process"
    return []

  _DDPMethod_jobRemove: (ids, options) ->
    check ids, Match.OneOf(Match.Where(_validId), [ Match.Where(_validId) ])
    check options, Match.Optional {}
    options ?= {}
    if _validId(ids)
      ids = [ids]
    return false if ids.length is 0
    num = @remove(
      {
        _id:
          $in: ids
        status:
          $in: @jobStatusRemovable
      }
    )
    if num > 0
      console.log "jobRemove succeeded"
      return true
    else
      console.warn "jobRemove failed"
    return false

  _DDPMethod_jobPause: (ids, options) ->
    check ids, Match.OneOf(Match.Where(_validId), [ Match.Where(_validId) ])
    check options, Match.Optional {}
    options ?= {}
    if _validId(ids)
      ids = [ids]
    return false if ids.length is 0
    time = new Date()
    num = @update(
      {
        _id:
          $in: ids
        status:
          $in: @jobStatusPausable
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

  _DDPMethod_jobResume: (ids, options) ->
    check ids, Match.OneOf(Match.Where(_validId), [ Match.Where(_validId) ])
    check options, Match.Optional {}
    options ?= {}
    if _validId(ids)
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
      @_promote_jobs? ids
      console.log "jobResume succeeded"
      return true
    else
      console.warn "jobResume failed"
    return false

  _DDPMethod_jobCancel: (ids, options) ->
    check ids, Match.OneOf(Match.Where(_validId), [ Match.Where(_validId) ])
    check options, Match.Optional
      antecedents: Match.Optional Boolean
      dependents: Match.Optional Boolean
    options ?= {}
    options.antecedents ?= false
    options.dependents ?= true
    if _validId(ids)
      ids = [ids]
    return false if ids.length is 0
    time = new Date()
    num = @update(
      {
        _id:
          $in: ids
        status:
          $in: @jobStatusCancellable
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
    cancelIds = @_idsOfDeps ids, options.antecedents, options.dependents, @jobStatusCancellable

    depsCancelled = false
    if cancelIds.length > 0
      depsCancelled = @_DDPMethod_jobCancel cancelIds, options

    if num > 0 or depsCancelled
      console.log "jobCancel succeeded"
      return true
    else
      console.warn "jobCancel failed"
    return false

  _DDPMethod_jobRestart: (ids, options) ->
    check ids, Match.OneOf(Match.Where(_validId), [ Match.Where(_validId) ])
    check options, Match.Optional
      retries: Match.Optional(Match.Where _validIntGTEOne)
      until: Match.Optional Date
      antecedents: Match.Optional Boolean
      dependents: Match.Optional Boolean
    options ?= {}
    options.retries ?= 1
    options.retries = @forever if options.retries > @forever
    options.dependents ?= false
    options.antecedents ?= true
    if _validId(ids)
      ids = [ids]
    return false if ids.length is 0
    console.log "Restarting: #{ids}"
    time = new Date()

    query =
      _id:
        $in: ids
      status:
        $in: @jobStatusRestartable

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
    restartIds = @_idsOfDeps ids, options.antecedents, options.dependents, @jobStatusRestartable

    depsRestarted = false
    if restartIds.length > 0
      depsRestarted = @_DDPMethod_jobRestart restartIds, options

    if num > 0 or depsRestarted
      @_promote_jobs? ids
      console.log "jobRestart succeeded"
      return true
    else
      console.warn "jobRestart failed"
    return false

  # Job creator methods

  _DDPMethod_jobSave: (doc, options) ->
    check doc, _validJobDoc()
    check options, Match.Optional
      cancelRepeats: Match.Optional Boolean
    check doc.status, Match.Where (v) ->
      Match.test(v, String) and v in [ 'waiting', 'paused' ]
    options ?= {}
    options.cancelRepeats ?= false
    doc.repeats = @forever if doc.repeats > @forever
    doc.retries = @forever if doc.retries > @forever

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
        @_promote_jobs? [doc._id]
        return doc._id
      else
        return null
    else
      if doc.repeats is @forever and options.cancelRepeats
        # If this is unlimited repeating job, then cancel any existing jobs of the same type
        @find(
          {
            type: doc.type
            status:
              $in: @jobStatusCancellable
          }
        ).forEach (d) => @_DDPMethod_jobCancel d._id, {}
      doc.created = time
      doc.log.push
        time: time
        runId: null
        level: 'info'
        message: "Job Submitted"

      newId = @insert doc
      @_promote_jobs? [newId]
      return newId

  # Worker methods

  _DDPMethod_jobProgress: (id, runId, completed, total, options) ->
    check id, Match.Where(_validId)
    check runId, Match.Where(_validId)
    check completed, Match.Where _validNumGTEZero
    check total, Match.Where _validNumGTZero
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

  _DDPMethod_jobLog: (id, runId, message, options) ->
    check id, Match.Where(_validId)
    check runId, Match.Where(_validId)
    check message, String
    check options, Match.Optional
      level: Match.Optional(Match.Where _validLogLevel)
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

  _DDPMethod_jobRerun: (id, options) ->
    check id, Match.Where(_validId)
    check options, Match.Optional
      repeats: Match.Optional(Match.Where _validIntGTEZero)
      until: Match.Optional Date
      wait: Match.Optional(Match.Where _validIntGTEZero)

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
      options.repeats = @forever if options.repeats > @forever
      options.until ?= doc.repeatUntil
      options.wait ?= 0
      return @_rerun_job doc, options.repeats, options.wait, options.until

    return false

  _DDPMethod_jobDone: (id, runId, result, options) ->
    check id, Match.Where(_validId)
    check runId, Match.Where(_validId)
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
        jobId = @_rerun_job doc

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

  _DDPMethod_jobFail: (id, runId, err, options) ->
    check id, Match.Where(_validId)
    check runId, Match.Where(_validId)
    check err, Object
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
          failures:
            err
          log:
            time: time
            runId: runId
            level: if newStatus is 'failed' then 'danger' else 'warning'
            message: "Job Failed with #{"Fatal" if options.fatal} Error: #{err.value if err.value? and typeof err.value is 'string'}."
      }
    )
    if newStatus is "failed" and num is 1
      # Cancel any dependent jobs too
      @find(
        {
          depends:
            $all: [ id ]
        }
      ).forEach (d) => @_DDPMethod_jobCancel d._id
    if num is 1
      console.log "jobFail succeeded"
      return true
    else
      console.warn "jobFail failed"
    return false

# Share these methods so they'll be available on server and client

share.JobCollectionBase = JobCollectionBase