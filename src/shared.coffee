############################################################################
#     Copyright (C) 2014-2017 by Vaughn Iverson
#     job-collection is free software released under the MIT/X11 license.
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
  Match.test(v, Match.OneOf(String, Mongo.Collection.ObjectID))

_validLog = () ->
  [{
      time: Date
      runId: Match.OneOf(Match.Where(_validId), null)
      level: Match.Where(_validLogLevel)
      message: String
      data: Match.Optional Object
  }]

_validProgress = () ->
  completed: Match.Where(_validNumGTEZero)
  total: Match.Where(_validNumGTEZero)
  percent: Match.Where(_validNumGTEZero)

_validLaterJSObj = () ->
  schedules: [ Object ]
  exceptions: Match.Optional [ Object ]

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
  workTimeout: Match.Optional Match.Where(_validIntGTEOne)
  expiresAfter: Match.Optional Date
  log: Match.Optional _validLog()
  progress: _validProgress()
  retries: Match.Where _validIntGTEZero
  retried: Match.Where _validIntGTEZero
  repeatRetries: Match.Optional Match.Where _validIntGTEZero
  retryUntil: Date
  retryWait: Match.Where _validIntGTEZero
  retryBackoff: Match.Where _validRetryBackoff
  repeats: Match.Where _validIntGTEZero
  repeated: Match.Where _validIntGTEZero
  repeatUntil: Date
  repeatWait: Match.OneOf(Match.Where(_validIntGTEZero), Match.Where(_validLaterJSObj))
  created: Date

_getAllProperties = (obj) ->
  names = new Set()
  properties = []
  while obj
    for name in Object.getOwnPropertyNames(obj) when name not in names
      properties.push([name, obj[name]])
      names.add(name)
    obj = Object.getPrototypeOf(obj)
  properties

class JobCollectionBase extends Mongo.Collection

  constructor: (root = 'queue', options = {}) ->
    options.noCollectionSuffix ?= false

    collectionName = root

    unless options.noCollectionSuffix
      collectionName += '.jobs'

    # Remove non-standard options before
    # calling Mongo.Collection constructor
    delete options.noCollectionSuffix

    Job.setDDP(options.connection, root)

    # Call super's constructor
    super collectionName, options

    unless @ instanceof Mongo.Collection
      throw new Meteor.Error 'The global definition of Mongo.Collection has changed since the job-collection package was loaded. Please ensure that any packages that redefine Mongo.Collection are loaded before job-collection.'

    unless Mongo.Collection is Mongo.Collection.prototype.constructor
      throw new Meteor.Error 'The global definition of Mongo.Collection has been patched by another package, and the prototype constructor has been left in an inconsistent state. Please see this link for a workaround: https://github.com/vsivsi/meteor-file-sample-app/issues/2#issuecomment-120780592'

    @root = root

    @later = later  # later object, for convenience

    @_createLogEntry = (message = '', runId = null, level = 'info', time = new Date(), data = null) ->
      l = { time: time, runId: runId, message: message, level: level }
      return l

    @_logMessage =
      'readied': (() -> @_createLogEntry "Promoted to ready").bind(@)
      'forced': ((id) -> @_createLogEntry "Dependencies force resolved", null, 'warning').bind(@)
      'rerun': ((id, runId) -> @_createLogEntry "Rerunning job", null, 'info', new Date(), {previousJob:{id:id,runId:runId}}).bind(@)
      'running': ((runId) -> @_createLogEntry "Job Running", runId).bind(@)
      'paused': (() -> @_createLogEntry "Job Paused").bind(@)
      'resumed': (() -> @_createLogEntry "Job Resumed").bind(@)
      'cancelled': (() -> @_createLogEntry "Job Cancelled", null, 'warning').bind(@)
      'restarted': (() -> @_createLogEntry "Job Restarted").bind(@)
      'resubmitted': (() -> @_createLogEntry "Job Resubmitted").bind(@)
      'submitted': (() -> @_createLogEntry "Job Submitted").bind(@)
      'completed': ((runId) -> @_createLogEntry "Job Completed", runId, 'success').bind(@)
      'resolved': ((id, runId) -> @_createLogEntry "Dependency resolved", null, 'info', new Date(), {dependency:{id:id,runId:runId}}).bind(@)
      'failed': ((runId, fatal, err) ->
        value = err.value
        msg = "Job Failed with#{if fatal then ' Fatal' else ''} Error#{if value? and typeof value is 'string' then ': ' + value else ''}."
        level = if fatal then 'danger' else 'warning'
        @_createLogEntry msg, runId, level).bind(@)

  _validNumGTEZero: _validNumGTEZero
  _validNumGTZero: _validNumGTZero
  _validNumGTEOne: _validNumGTEOne
  _validIntGTEZero: _validIntGTEZero
  _validIntGTEOne: _validIntGTEOne
  _validStatus: _validStatus
  _validLogLevel: _validLogLevel
  _validRetryBackoff: _validRetryBackoff
  _validId: _validId
  _validLog: _validLog
  _validProgress: _validProgress
  _validJobDoc: _validJobDoc

  jobLogLevels: Job.jobLogLevels
  jobPriorities: Job.jobPriorities
  jobStatuses: Job.jobStatuses
  jobStatusCancellable: Job.jobStatusCancellable
  jobStatusPausable: Job.jobStatusPausable
  jobStatusRemovable: Job.jobStatusRemovable
  jobStatusRestartable: Job.jobStatusRestartable
  forever: Job.forever
  foreverDate: Job.foreverDate

  ddpMethods: Job.ddpMethods
  ddpPermissionLevels: Job.ddpPermissionLevels
  ddpMethodPermissions: Job.ddpMethodPermissions

  processJobs: (params...) -> new Job.processJobs @root, params...
  getJob: (params...) -> Job.getJob @root, params...
  getWork: (params...) -> Job.getWork @root, params...
  getJobs: (params...) -> Job.getJobs @root, params...
  readyJobs: (params...) -> Job.readyJobs @root, params...
  cancelJobs: (params...) -> Job.cancelJobs @root, params...
  pauseJobs: (params...) -> Job.pauseJobs @root, params...
  resumeJobs: (params...) -> Job.resumeJobs @root, params...
  restartJobs: (params...) -> Job.restartJobs @root, params...
  removeJobs: (params...) -> Job.removeJobs @root, params...

  setDDP: (params...) -> Job.setDDP params...

  startJobServer: (params...) -> Job.startJobServer @root, params...
  shutdownJobServer: (params...) -> Job.shutdownJobServer @root, params...

  # These are deprecated and will be removed
  startJobs: (params...) -> Job.startJobs @root, params...
  stopJobs: (params...) -> Job.stopJobs @root, params...

  jobDocPattern: _validJobDoc()

  # Warning Stubs for server-only calls
  allow: () -> throw new Error "Server-only function jc.allow() invoked on client."
  deny: () -> throw new Error "Server-only function jc.deny() invoked on client."
  promote: () -> throw new Error "Server-only function jc.promote() invoked on client."
  setLogStream: () -> throw new Error "Server-only function jc.setLogStream() invoked on client."

  # Warning Stubs for client-only calls
  logConsole: () -> throw new Error "Client-only function jc.logConsole() invoked on server."

  # Deprecated. Remove in next major version
  makeJob: do () ->
    dep = false
    (params...) ->
      unless dep
        dep = true
        console.warn "WARNING: jc.makeJob() has been deprecated. Use new Job(jc, doc) instead."
      new Job @root, params...

  # Deprecated. Remove in next major version
  createJob: do () ->
    dep = false
    (params...) ->
      unless dep
        dep = true
        console.warn "WARNING: jc.createJob() has been deprecated. Use new Job(jc, type, data) instead."
      new Job @root, params...

  _methodWrapper: (method, func) ->
    toLog = @_toLog
    unblockDDPMethods = @_unblockDDPMethods ? false
    # Return the wrapper function that the Meteor method will actually invoke
    return (params...) ->
      user = this.userId ? "[UNAUTHENTICATED]"
      toLog user, method, "params: " + JSON.stringify(params)
      this.unblock() if unblockDDPMethods
      retval = func(params...)
      toLog user, method, "returned: " + JSON.stringify(retval)
      return retval

  _generateMethods: () ->
    methodsOut = {}
    methodPrefix = '_DDPMethod_'
    for [methodName, methodFunc] in _getAllProperties(@) when methodName[0...methodPrefix.length] is methodPrefix
      baseMethodName = methodName[methodPrefix.length..]
      methodsOut["#{@root}_#{baseMethodName}"] = @_methodWrapper(baseMethodName, methodFunc.bind(@))
    return methodsOut

  _idsOfDeps: (ids, antecedents, dependents, jobStatuses) ->
    # Cancel the entire tree of antecedents and/or dependents
    # Dependents: jobs that list one of the ids in their depends list
    # Antecedents: jobs with an id listed in the depends list of one of the jobs in ids
    dependsQuery = []
    dependsIds = []
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
          transform: null
        }
      ).forEach (d) -> antsArray.push(i) for i in d.depends unless i in antsArray
      if antsArray.length > 0
        dependsQuery.push
          _id:
            $in: antsArray
    if dependsQuery.length > 0
      @find(
        {
          status:
            $in: jobStatuses
          $or: dependsQuery
        }
        {
          fields:
            _id: 1
          transform: null
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
    delete doc.failures
    delete doc.expiresAfter
    delete doc.workTimeout
    doc.runId = null
    doc.status = "waiting"
    doc.repeatRetries = if doc.repeatRetries? then doc.repeatRetries else doc.retries + doc.retried
    doc.retries = doc.repeatRetries
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
    if logObj = @_logMessage.rerun id, runId
      doc.log = [logObj]
    else
      doc.log = []

    doc.after = new Date(time.valueOf() + wait)
    if jobId = @insert doc
      @_DDPMethod_jobReady jobId
      return jobId
    else
      console.warn "Job rerun/repeat failed to reschedule!", id, runId
    return null

  _checkDeps: (job, dryRun = true) ->
    cancel = false
    resolved = []
    failed = []
    cancelled = []
    removed = []
    log = []
    if job.depends.length > 0
      deps = @find({_id: { $in: job.depends }},{ fields: { _id: 1, runId: 1, status: 1 } }).fetch()

      if deps.length isnt job.depends.length
        foundIds = deps.map (d) -> d._id
        for j in job.depends when not (j in foundIds)
          @_DDPMethod_jobLog job._id, null, "Antecedent job #{j} missing at save" unless dryRun
          removed.push j
        cancel = true

      for depJob in deps
        unless depJob.status in @jobStatusCancellable
          switch depJob.status
            when "completed"
              resolved.push depJob._id
              log.push @_logMessage.resolved depJob._id, depJob.runId
            when "failed"
              cancel = true
              failed.push depJob._id
              @_DDPMethod_jobLog job._id, null, "Antecedent job failed before save" unless dryRun
            when "cancelled"
              cancel = true
              cancelled.push depJob._id
              @_DDPMethod_jobLog job._id, null, "Antecedent job cancelled before save" unless dryRun
            else  # Unknown status
              throw new Meteor.Error "Unknown status in jobSave Dependency check"

      unless resolved.length is 0 or dryRun
        mods =
          $pull:
            depends:
              $in: resolved
          $push:
            resolved:
              $each: resolved
            log:
              $each: log

        n = @update(
          {
            _id: job._id
            status: 'waiting'
          }
          mods
        )

        unless n
          console.warn "Update for job #{job._id} during dependency check failed."

      if cancel and not dryRun
        @_DDPMethod_jobCancel job._id
        return false

    if dryRun
      if cancel or resolved.length > 0
        return {
          jobId: job._id
          resolved: resolved
          failed: failed
          cancelled: cancelled
          removed: removed
        }
      else
        return false
    else
      return true

  _DDPMethod_startJobServer: (options) ->
    check options, Match.Optional {}
    options ?= {}
    # The client can't actually do this, so skip it
    unless @isSimulation
      Meteor.clearTimeout(@stopped) if @stopped and @stopped isnt true
      @stopped = false
    return true

  _DDPMethod_startJobs: do () =>
    depFlag = false
    (options) ->
      unless depFlag
        depFlag = true
        console.warn "Deprecation Warning: jc.startJobs() has been renamed to jc.startJobServer()"
      return @_DDPMethod_startJobServer options

  _DDPMethod_shutdownJobServer: (options) ->
    check options, Match.Optional
      timeout: Match.Optional(Match.Where _validIntGTEOne)
    options ?= {}
    options.timeout ?= 60*1000

    # The client can't actually do any of this, so skip it
    unless @isSimulation
      Meteor.clearTimeout(@stopped) if @stopped and @stopped isnt true
      @stopped = Meteor.setTimeout(
        () =>
          cursor = @find(
            {
              status: 'running'
            },
            {
              transform: null
            }
          )
          failedJobs = cursor.count()
          console.warn "Failing #{failedJobs} jobs on queue stop." if failedJobs isnt 0
          cursor.forEach (d) => @_DDPMethod_jobFail d._id, d.runId, "Running at Job Server shutdown."
          if @logStream? # Shutting down closes the logStream!
            @logStream.end()
            @logStream = null
        options.timeout
      )
    return true

  _DDPMethod_stopJobs: do () =>
    depFlag = false
    (options) ->
      unless depFlag
        depFlag = true
        console.warn "Deprecation Warning: jc.stopJobs() has been renamed to jc.shutdownJobServer()"
      return @_DDPMethod_shutdownJobServer options

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
    fields = {_private:0}
    fields.log = 0 if !options.getLog
    fields.failures = 0 if !options.getFailures
    docs = @find(
      {
        _id:
          $in: ids
      }
      {
        fields: fields
        transform: null
      }
    ).fetch()
    if docs?.length
      if @scrub?
        docs = (@scrub d for d in docs)
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
      workTimeout: Match.Optional(Match.Where _validIntGTEOne)

    # Don't simulate getWork!
    if @isSimulation
      return

    options ?= {}
    options.maxJobs ?= 1
    # Don't put out any more jobs while shutting down
    if @stopped
      return []

    # Support string types or arrays of string types
    if typeof type is 'string'
      type = [ type ]
    time = new Date()
    docs = []
    runId = @_makeNewID() # This is meteor internal, but it will fail hard if it goes away.

    while docs.length < options.maxJobs

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
          limit: options.maxJobs - docs.length # never ask for more than is needed
          fields:
            _id: 1
          transform: null
        }).map (d) -> d._id

      unless ids?.length > 0
        break  # Don't keep looping when there's no available work

      mods =
        $set:
          status: 'running'
          runId: runId
          updated: time
        $inc:
          retries: -1
          retried: 1

      if logObj = @_logMessage.running runId
        mods.$push =
          log: logObj

      if options.workTimeout?
        mods.$set.workTimeout = options.workTimeout
        mods.$set.expiresAfter = new Date(time.valueOf() + options.workTimeout)
      else
        mods.$unset ?= {}
        mods.$unset.workTimeout = ""
        mods.$unset.expiresAfter = ""

      num = @update(
        {
          _id:
            $in: ids
          status: 'ready'
          runId: null
        }
        mods
        {
          multi: true
        }
      )

      if num > 0
        foundDocs = @find(
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
            transform: null
          }
        ).fetch()

        if foundDocs?.length > 0
          if @scrub?
            foundDocs = (@scrub d for d in foundDocs)
          check docs, [ _validJobDoc() ]
          docs = docs.concat foundDocs
        # else
        #   console.warn "getWork: find after update failed"
    return docs

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

    mods =
      $set:
        status: "paused"
        updated: time

    if logObj = @_logMessage.paused()
      mods.$push =
        log: logObj

    num = @update(
      {
        _id:
          $in: ids
        status:
          $in: @jobStatusPausable
      }
      mods
      {
        multi: true
      }
    )
    if num > 0
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
    mods =
      $set:
        status: "waiting"
        updated: time

    if logObj = @_logMessage.resumed()
      mods.$push =
        log: logObj

    num = @update(
      {
        _id:
          $in: ids
        status: "paused"
        updated:
          $ne: time
      }
      mods
      {
        multi: true
      }
    )
    if num > 0
      @_DDPMethod_jobReady ids
      return true
    else
      console.warn "jobResume failed"
    return false

  _DDPMethod_jobReady: (ids, options) ->
    check ids, Match.OneOf(Match.Where(_validId), [ Match.Where(_validId) ])
    check options, Match.Optional
      force: Match.Optional Boolean
      time: Match.Optional Date

    # Don't simulate jobReady. It has a strong chance of causing issues with
    # Meteor on the client, particularly if an observeChanges() is triggering
    # a processJobs queue (which in turn sets timers.)
    if @isSimulation
      return

    now = new Date()

    options ?= {}
    options.force ?= false
    options.time ?= now

    if _validId(ids)
      ids = [ids]

    query =
      status: "waiting"
      after:
        $lte: options.time

    mods =
      $set:
        status: "ready"
        updated: now

    if ids.length > 0
      query._id =
        $in: ids
      mods.$set.after = now

    logObj = []

    if options.force
      mods.$set.depends = []  # Don't move to resolved, because they weren't!
      l = @_logMessage.forced()
      logObj.push l if l
    else
      query.depends =
        $size: 0

    l = @_logMessage.readied()
    logObj.push l if l

    if logObj.length > 0
      mods.$push =
        log:
          $each: logObj

    num = @update(
      query
      mods
      {
        multi: true
      }
    )

    if num > 0
      return true
    else
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

    mods =
      $set:
        status: "cancelled"
        runId: null
        progress:
          completed: 0
          total: 1
          percent: 0
        updated: time

    if logObj = @_logMessage.cancelled()
      mods.$push =
        log: logObj

    num = @update(
      {
        _id:
          $in: ids
        status:
          $in: @jobStatusCancellable
      }
      mods
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
      return true
    else
      console.warn "jobCancel failed"
    return false

  _DDPMethod_jobRestart: (ids, options) ->
    check ids, Match.OneOf(Match.Where(_validId), [ Match.Where(_validId) ])
    check options, Match.Optional
      retries: Match.Optional(Match.Where _validIntGTEZero)
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

    if logObj = @_logMessage.restarted()
      mods.$push =
        log: logObj

    if options.until?
      mods.$set.retryUntil = options.until

    num = @update query, mods, {multi: true}

    # Restart the entire tree of dependents
    restartIds = @_idsOfDeps ids, options.antecedents, options.dependents, @jobStatusRestartable

    depsRestarted = false
    if restartIds.length > 0
      depsRestarted = @_DDPMethod_jobRestart restartIds, options

    if num > 0 or depsRestarted
      @_DDPMethod_jobReady ids
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

    # If doc.repeatWait is a later.js object, then don't run before
    # the first valid scheduled time that occurs after doc.after
    if @later? and typeof doc.repeatWait isnt 'number'
      # Using a workaround to find next time after doc.after.
      # See: https://github.com/vsivsi/meteor-job-collection/issues/217
      schedule = @later?.schedule(doc.repeatWait)
      unless schedule and next = schedule.next(2, schedule.prev(1, doc.after))[1]
        console.warn "No valid available later.js times in schedule after #{doc.after}"
        return null
      nextDate = new Date(next)
      unless nextDate <= doc.repeatUntil
        console.warn "No valid available later.js times in schedule before #{doc.repeatUntil}"
        return null
      doc.after = nextDate
    else if not @later? and doc.repeatWait isnt 'number'
      console.warn "Later.js not loaded..."
      return null

    if doc._id

      mods =
        $set:
          status: 'waiting'
          data: doc.data
          retries: doc.retries
          repeatRetries: if doc.repeatRetries? then doc.repeatRetries else doc.retries + doc.retried
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

      if logObj = @_logMessage.resubmitted()
        mods.$push =
          log: logObj

      num = @update(
        {
          _id: doc._id
          status: 'paused'
          runId: null
        }
        mods
      )

      if num and @_checkDeps doc, false
        @_DDPMethod_jobReady doc._id
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
          },
          {
            transform: null
          }
        ).forEach (d) => @_DDPMethod_jobCancel d._id, {}
      doc.created = time
      doc.log.push @_logMessage.submitted()
      doc._id = @insert doc
      if doc._id and @_checkDeps doc, false
        @_DDPMethod_jobReady doc._id
        return doc._id
      else
        return null

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

    job = @findOne { _id: id }, { fields: { workTimeout: 1 } }

    mods =
      $set:
        progress: progress
        updated: time

    if job?.workTimeout?
      mods.$set.expiresAfter = new Date(time.valueOf() + job.workTimeout)

    num = @update(
      {
        _id: id
        runId: runId
        status: "running"
      }
      mods
    )

    if num is 1
      return true
    else
      console.warn "jobProgress failed"
    return false

  _DDPMethod_jobLog: (id, runId, message, options) ->
    check id, Match.Where(_validId)
    check runId, Match.OneOf(Match.Where(_validId), null)
    check message, String
    check options, Match.Optional
      level: Match.Optional(Match.Where _validLogLevel)
      data: Match.Optional Object
    options ?= {}
    time = new Date()
    logObj =
        time: time
        runId: runId
        level: options.level ? 'info'
        message: message
    logObj.data = options.data if options.data?

    job = @findOne { _id: id }, { fields: { status: 1, workTimeout: 1 } }

    mods =
      $push:
        log: logObj
      $set:
        updated: time

    if job?.workTimeout? and job.status is 'running'
      mods.$set.expiresAfter = new Date(time.valueOf() + job.workTimeout)

    num = @update(
      {
        _id: id
      }
      mods
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
      wait: Match.OneOf(Match.Where(_validIntGTEZero), Match.Where(_validLaterJSObj))

    doc = @findOne(
      {
        _id: id
        status: "completed"
      }
      {
        fields:
          result: 0
          failures: 0
          log: 0
          progress: 0
          updated: 0
          after: 0
          status: 0
        transform: null
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
    check options, Match.Optional
      repeatId: Match.Optional Boolean
      delayDeps: Match.Optional(Match.Where(_validIntGTEZero))

    options ?= { repeatId: false }
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
          failures: 0
          updated: 0
          after: 0
          status: 0
        transform: null
      }
    )
    unless doc?
      unless @isSimulation
        console.warn "Running job not found", id, runId
      return false

    mods =
      $set:
        status: "completed"
        result: result
        progress:
          completed: doc.progress.total or 1
          total: doc.progress.total or 1
          percent: 100
        updated: time

    if logObj = @_logMessage.completed runId
      mods.$push =
        log: logObj

    num = @update(
      {
        _id: id
        runId: runId
        status: "running"
      }
      mods
    )
    if num is 1
      if doc.repeats > 0
        if typeof doc.repeatWait is 'number'
          if doc.repeatUntil - doc.repeatWait >= time
            jobId = @_rerun_job doc
        else
          # This code prevents a job that just ran and finished
          # instantly from being immediately rerun on the same occurance
          next = @later?.schedule(doc.repeatWait).next(2)
          if next and next.length > 0
            d = new Date(next[0])
            if (d - time > 500) or (next.length > 1)
              if d - time <= 500
                d = new Date(next[1])
              wait = d - time
              if doc.repeatUntil - wait >= time
                jobId = @_rerun_job doc, doc.repeats - 1, wait

      # Resolve depends
      ids = @find(
        {
          depends:
            $all: [ id ]
        },
        {
          transform: null
          fields:
            _id: 1
        }
      ).fetch().map (d) => d._id

      if ids.length > 0

        mods =
          $pull:
            depends: id
          $push:
            resolved: id

        if options.delayDeps?
          after = new Date(time.valueOf() + options.delayDeps)
          mods.$max =
            after: after

        if logObj = @_logMessage.resolved id, runId
          mods.$push.log = logObj

        n = @update(
          {
            _id:
              $in: ids
          }
          mods
          {
            multi: true
          }
        )
        if n isnt ids.length
          console.warn "Not all dependent jobs were resolved #{ids.length} > #{n}"
        # Try to promote any jobs that just had a dependency resolved
        @_DDPMethod_jobReady ids
      if options.repeatId and jobId?
        return jobId
      else
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
          failures: 0
          progress: 0
          updated: 0
          after: 0
          runId: 0
          status: 0
        transform: null
      }
    )
    unless doc?
      unless @isSimulation
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

    err.runId = runId  # Link each failure to the run that generated it.

    mods =
      $set:
        status: newStatus
        runId: null
        after: after
        updated: time
      $push:
        failures:
          err

    if logObj = @_logMessage.failed runId, newStatus is 'failed', err
      mods.$push.log = logObj

    num = @update(
      {
        _id: id
        runId: runId
        status: "running"
      }
      mods
    )
    if newStatus is "failed" and num is 1
      # Cancel any dependent jobs too
      @find(
        {
          depends:
            $all: [ id ]
        },
        {
          transform: null
        }
      ).forEach (d) => @_DDPMethod_jobCancel d._id
    if num is 1
      return true
    else
      console.warn "jobFail failed"
    return false

# Share these methods so they'll be available on server and client

share.JobCollectionBase = JobCollectionBase
