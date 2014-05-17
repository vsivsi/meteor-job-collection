############################################################################
#     Copyright (C) 2014 by Vaughn Iverson
#     jobCollection is free software released under the MIT/X11 license.
#     See included LICENSE file for details.
############################################################################

if Meteor.isServer

  ###############################################################
  # jobCollection server DDP methods

  validIntGTEZero = (v) ->
    Match.test(v, Match.Integer) and v >= 0

  validIntGTEOne = (v) ->
    Match.test(v, Match.Integer) and v >= 1

  validNumGTEZero = (v) ->
    Match.test(v, Number) and v >= 0.0

  validStatus = (v) ->
    Match.test(v, String) and v in Job.jobStatuses

  validLog = () ->
    [ { time: Date, runId: Match.OneOf(Meteor.Collection.ObjectID, null), message: String } ]

  validProgress = () ->
    completed: Match.Where(validNumGTEZero)
    total: Match.Where(validNumGTEZero)
    percent: Match.Where(validNumGTEZero)

  validJobDoc = () ->
    _id: Match.Optional Match.OneOf(Meteor.Collection.ObjectID, null)
    runId: Match.OneOf(Meteor.Collection.ObjectID, null)
    type: String
    status: Match.Where validStatus
    data: Object
    priority: Match.Integer
    depends: [ Meteor.Collection.ObjectID ]
    after: Date
    updated: Date
    log: Match.Optional validLog()
    progress: validProgress()
    retries: Match.Where validNumGTEZero
    retried: Match.Where validNumGTEZero
    retryWait: Match.Where validNumGTEZero
    repeats: Match.Where validNumGTEZero
    repeated: Match.Where validNumGTEZero
    repeatWait: Match.Where validNumGTEZero

  serverMethods =
    # Job manager methods
    pauseJobs: (state = true, types = []) ->
      check state, Boolean
      check types, [String]
      if types
        for t in types
          @paused[t] = state
      else
        @paused = state
      return true

    shutdownJobs: () ->
      @shutdown = true
      return true

    getJob: (id) ->
      check id, Meteor.Collection.ObjectID
      console.log "Get: ", id
      if id
        d = @findOne(
          {
            _id: id
          }
          {
            fields:
              log: 0
          }
        )
        if d
          console.log "get method Got a job", d
          check d, validJobDoc()
          return d
        else
          console.warn "Get failed job"
      else
        console.warn "Bad id in get", id
      return null

    getLog: (id) ->
      check id, Meteor.Collection.ObjectID
      console.log "Get: ", id
      if id
        d = @findOne(
          {
            _id: id
          }
          {
            fields:
              log: 1
          }
        )
        if d
          console.log "get method Got a log", d
          check d, validJobDoc()
          return d
        else
          console.warn "Get failed log"
      else
        console.warn "Bad id in get log", id
      return null

    jobRemove: (id) ->
      check id, Meteor.Collection.ObjectID
      if id
        num = @remove(
          {
            _id: id
            status:
              $in: ["cancelled", "failed", "completed"]
          }
        )
        if num is 1
          console.log "jobRemove succeeded"
          return true
        else
          console.warn "jobRemove failed"
      else
        console.warn "jobRemoved something's wrong with done: #{id}"
      return false

    jobPause: (id) ->
      check id, Meteor.Collection.ObjectID
      if id
        time = new Date()
        num = @update(
          {
            _id: id
            status:
              $in: ["ready", "waiting"]
          }
          {
            $set:
              status: "paused"
              updated: time
          }
        )
        if num is 1
          console.log "jobPause succeeded"
          return true
        else
          num = @update(
            {
              _id: id
              status: "paused"
            }
            {
              $set:
                status: "waiting"
                updated: time
            }
          )
          if num is 1
            console.log "jobPause succeeded"
            return true
          else
            console.warn "jobPause failed"
      else
        console.warn "jobPause: something's wrong with done: #{id}", runId, err
      return false

    jobCancel: (id) ->
      check id, Meteor.Collection.ObjectID
      if id
        time = new Date()
        num = @update(
          {
            _id: id
            status:
              $in: ["ready", "waiting", "running", "paused"]
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
                message: "Cancelled"
          }
        )
        if num is 1
          # Cancel the entire tree of dependents
          @find(
            {
              depends:
                $all: [ id ]
            }
          ).forEach (d) => serverMethods.jobCancel.bind(@)(d._id)

          console.log "jobCancel succeeded"
          return true
        else
          console.warn "jobCancel failed"
      else
        console.warn "jobCancel: something's wrong with done: #{id}", runId, err
      return false

    jobRestart: (id, retries = 1) ->
      check id, Meteor.Collection.ObjectID
      check retries, Match.Where validIntGTEOne
      if id
        time = new Date()
        num = @update(
          {
            _id: id
            status:
              $in: ["cancelled", "failed"]
          }
          {
            $set:
              status: "waiting"
              progress:
                completed: 0
                total: 1
                percent: 0
              updated: time
            $inc:
              retries: retries
          }
        )
        if num is 1
          # Cancel the entire tree of dependents
          @find(
            {
              depends:
                $all: [ id ]
            }
          ).forEach (d) => serverMethods.jobRestart.bind(@)(d._id)
          console.log "jobRestart succeeded"
          return true
        else
          console.warn "jobRestart failed"
      else
        console.warn "jobRestart: something's wrong with done: #{id}", runId, err
      return false

    # Job creator methods

    jobSubmit: (doc) ->
      check doc, validJobDoc()
      if doc._id
        num = @update(
          {
            _id: doc._id
            runId: null
          }
          {
            $set:
              retries: doc.retries
              retryWait: doc.retryWait
              repeats: doc.repeats
              repeatWait: doc.repeatWait
              depends: doc.depends
              priority: doc.priority
              after: doc.after
          }
        )
      else
        console.log doc
        return @insert doc

    # Worker methods

    getWork: (type, max = 1) ->
      check type, Match.OneOf String, [ String ]
      # check max, Match.Where validIntGTEOne
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
            priority: -1
            after: 1
          limit: max
          fields:
            _id: 1
        }).map (d) -> d._id

      if ids?.length
        runId = new Meteor.Collection.ObjectID()
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
        console.log "Didn't find a job to process"
      return []

    jobProgress: (id, runId, progress) ->
      check id, Meteor.Collection.ObjectID
      check runId, Meteor.Collection.ObjectID
      check progress, validProgress()
      if id and runId and progress
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
      else
        console.warn "jobProgress: something's wrong with progress: #{id}", progress
      return false

    jobLog: (id, runId, message) ->
      check id, Meteor.Collection.ObjectID
      check runId, Meteor.Collection.ObjectID
      check message, String
      if id and message
        time = new Date()
        console.log "Logging a message", id, runId, message
        num = @update(
          {
            _id: id
          }
          {
            $push:
              log:
                time: time
                runId: runId
                message: message
            $set:
              updated: time
          }
        )
        if num is 1
          console.log "jobLog succeeded", message
          return true
        else
          console.warn "jobLog failed"
      else
        console.warn "jobLog: something's wrong with progress: #{id}", message
      return false

    jobDone: (id, runId) ->
      check id, Meteor.Collection.ObjectID
      check runId, Meteor.Collection.ObjectID
      if id and runId
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
        num = @update(
          {
            _id: id
            runId: runId
            status: "running"
          }
          {
            $set:
              status: "completed"
              progress:
                completed: 1
                total: 1
                percent: 100
              updated: time
          }
        )
        if num is 1
          if doc.repeats > 0
          # Repeat? if so, make a new job from the old one
            delete doc._id
            doc.runId = null
            doc.status = "waiting"
            doc.retries = doc.retries + doc.retried
            doc.retried = 0
            doc.repeats = doc.repeats - 1
            doc.repeated = doc.repeated + 1
            doc.updated = time
            doc.progress = { completed: 0, total: 1, percent: 0 }
            doc.log = [{ time: time, runId: null, message: "Repeating job #{id} from run #{runId}" }]
            doc.after = new Date(time.valueOf() + doc.repeatWait)
            jobId = @insert doc
            unless jobId
              console.warn "Repeating job failed to reschedule!", id, runId
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
                log:
                  time: time
                  runId: null
                  message: "Dependency resolved for #{id} by #{runId}"
            }
          )
          console.log "Job #{id} Resolved #{n} depends"
          console.log "jobDone succeeded"
          return true
        else
          console.warn "jobDone failed"
      else
        console.warn "jobDone: something's wrong with done: #{id}", runId
      return false

    jobFail: (id, runId, err) ->
      check id, Meteor.Collection.ObjectID
      check runId, Meteor.Collection.ObjectID
      check err, String
      if id and runId
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
        newStatus = if doc.retries > 0 then "waiting" else "failed"
        num = @update(
          {
            _id: id
            runId: runId
            status: "running" }
          {
            $set:
              status: newStatus
              runId: null
              after: new Date(time.valueOf() + doc.retryWait)
              progress:
                completed: 0
                total: 1
                percent: 0
              updated: time
            $push:
              log:
                time: time
                runId: runId
                message: "Job Failed with Error #{err}"
          }
        )
        if newStatus is "failed" and num is 1
          # Fail any dependent jobs too
          n = @update(
            {
              status: "waiting"
              depends:
                $all: [ id ]
            }
            {
              $set:
                status: "failed"
                runId: null
                updated: time
              $push:
                log:
                  time: time
                  runId: null
                  message: "Job Failed due to failure of dependancy #{id} with Error #{err}"
            }
            { multi: true }
          )
          console.log "Failed #{n} dependent jobs"
        if num is 1
          console.log "jobFail succeeded"
          return true
        else
          console.warn "jobFail failed"
      else
        console.warn "jobFail: something's wrong with done: #{id}", runId, err
      return false

  ################################################################
  ## jobCollection server class

  class jobCollection extends Meteor.Collection

    constructor: (@root = 'queue', options = {}) ->
      unless @ instanceof jobCollection
        return new jobCollection(@root, options)

      # Call super's constructor
      super @root + '.jobs', { idGeneration: 'MONGO' }
      @shutdown = false

      # No client mutators allowed
      @deny
        update: () => true
        insert: () => true
        remove: () => true

      @promote()
      @expire(60000)

      @logStream = options.logStream ? null

      @permissions = options.permissions ? { allow: true, deny: false }

      Meteor.methods(@_generateMethods serverMethods)

    _method_wrapper: (method, func) ->

      toLog = (userId, message) =>
        # console.warn "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
        @logStream?.write "#{new Date()}, #{userId}, #{method}, #{message}\n"

      myTypeof = (val) ->
        type = typeof val
        type = 'array' if type is 'object' and type instanceof Array
        return type

      permitted = (userId, params) =>

        performTest = (test, def) =>
          switch myTypeof test
            when 'boolean' then test
            when 'array' then userId in test
            when 'function' then test userId, method
            when 'object'
              methodType = myTypeof test?[method]
              switch methodType
                when 'boolean' then test[method]
                when 'array' then userId in test[method]
                when 'function' then test?[method]? userId, params
                else def
            else def

        return performTest(@permissions.allow, true) and not performTest(@permissions.deny, false)

      # Return the wrapper function that the Meteor method will actually invoke
      return (params...) ->
        user = this.userId ? "[UNAUTHENTICATED]"
        unless this.connection
          user = "[SERVER]"
        # console.log "!!!!!!", JSON.stringify params
        toLog user, "params: " + JSON.stringify(params)
        unless this.connection and not permitted(this.userId, params)
          retval = func(params...)
          toLog user, "returned: " + JSON.stringify(retval)
          return retval
        else
          toLog this.userId, "UNAUTHORIZED."
          throw new Meteor.Error 403, "Method not authorized", "Authenticated user is not permitted to invoke this method."

    _generateMethods: (methods) ->
      methodsOut = {}
      methodsOut["#{methodName}_#{root}"] = @_method_wrapper(methodName, methodFunc.bind(@)) for methodName, methodFunc of methods
      return methodsOut

    createJob: (params...) -> new Job @root, params...

    getJob: (params...) -> Job.getJob @root, params...

    getWork: (params...) -> Job.getWork @root, params...

    promote: (milliseconds = 15*1000) ->
      if typeof milliseconds is 'number' and milliseconds > 1000
        if @interval
          Meteor.clearInterval @interval
        @interval = Meteor.setInterval @_poll.bind(@), milliseconds
      else
        console.warn "jobCollection.promote: invalid timeout or limit: #{@root}, #{milliseconds}, #{limit}"

    expire: (milliseconds = 2*60*1000) ->
      if typeof milliseconds is 'number' and milliseconds > 1000
        @expireAfter = milliseconds

    _poll: () ->
      time = new Date()
      num = @update(
        { status: "waiting", after: { $lte: time }, depends: { $size: 0 }}
        { $set: { status: "ready", updated: time }, $push: { log: { time: time, runId: null, message: "Promoted to ready" }}}
        { multi: true })
      console.log "Ready fired: #{num} jobs promoted"

      exptime = new Date( time.valueOf() - @expireAfter )
      console.log "checking for expiration times before", exptime

      num = @update(
        { status: "running", updated: { $lte: exptime }, retries: { $gt: 0 }}
        { $set: { status: "ready", runId: null, updated: time, progress: { completed: 0, total: 1, percent: 0 } }, $push: { log: { time: time, runId: null, message: "Expired to retry" }}}
        { multi: true })
      console.log "Expired #{num} dead jobs, waiting to run"

      cursor = @find({ status: "running", updated: { $lte: exptime }, retries: 0})
      num = cursor.count()
      cursor.forEach (d) =>
        id = d._id
        n = @update(
          { _id: id, status: "running", updated: { $lte: exptime }, retries: 0}
          { $set: { status: "failed", runId: null, updated: time, progress: { completed: 0, total: 1, percent: 0 } }, $push: { log: { time: time, runId: null, message: "Expired to failure" }}}
        )
        if n is 1
          n = @update(
            {
              status: "waiting"
              depends:
                $all: [ id ]
            }
            {
              $set:
                status: "failed"
                runId: null
                updated: time
              $push:
                log:
                  time: time
                  runId: null
                  message: "Job Failed due to failure of dependancy #{id} by expiration"
            }
            { multi: true }
          )
          console.log "Failed #{n} dependent jobs"

      console.log "Expired #{num} dead jobs, failed"
