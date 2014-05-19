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

  validNumGTZero = (v) ->
    Match.test(v, Number) and v > 0.0

  validStatus = (v) ->
    Match.test(v, String) and v in Job.jobStatuses

  validLogLevel = (v) ->
    Match.test(v, String) and v in Job.jobLogLevels

  validLog = () ->
    [ { time: Date, runId: Match.OneOf(Meteor.Collection.ObjectID, null), level: String, message: String } ]

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

    startJobs: (options) ->
      check options, Match.Optional {}
      options ?= {}
      Meteor.clearTimeout(@stopped) if @stopped and @stopped isnt true
      @stopped = false
      return true

    stopJobs: (options) ->
      check options, Match.Optional
        timeout: Match.Optional(Match.Where validIntGTEOne)
      options ?= {}
      options.timeout ?= 60*1000
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
        options.timeout
      )
      return true

    getJob: (id, options) ->
      check id, Meteor.Collection.ObjectID
      check options, Match.Optional
        getLog: Match.Optional Boolean
      options ?= {}
      options.getLog ?= false
      console.log "Get: ", id
      if id
        d = @findOne(
          {
            _id: id
          }
          {
            fields:
              log: if options.getLog then 1 else 0
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
            priority: -1
            after: 1
          limit: options.maxJobs ? 1
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

    jobRemove: (id, options) ->
      check id, Meteor.Collection.ObjectID
      check options, Match.Optional {}
      options ?= {}
      if id
        num = @remove(
          {
            _id: id
            status:
              $in: Job.jobStatusRemovable
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

    jobPause: (id, options) ->
      check id, Meteor.Collection.ObjectID
      check options, Match.Optional {}
      options ?= {}
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
            $push:
              log:
                time: time
                runId: null
                message: "Job Paused"
          }
        )
        unless num is 1
          num = @update(
            {
              _id: id
              status: "paused"
            }
            {
              $set:
                status: "waiting"
                updated: time
              $push:
                log:
                  time: time
                  runId: null
                  message: "Job Unpaused"
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

    jobCancel: (id, options) ->
      check id, Meteor.Collection.ObjectID
      check options, Match.Optional
        antecedents: Match.Optional Boolean
      options ?= {}
      options.antecedents ?= true
      if id
        time = new Date()
        num = @update(
          {
            _id: id
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
        )
        if num is 1
          # Cancel the entire tree of dependents
          dependQuery = [
            depends:
              $all: [ id ]
          ]
          if options.antecedents
            doc = @findOne(
              {
                _id: id
              }
              {
                fields:
                  depends: 1
              }
            )
            if doc
              dependQuery.push
                _id:
                  $in: doc.depends
          @find(
            {
              status:
                $in: Job.jobStatusCancellable
              $or: dependQuery
            }
          ).forEach (d) => serverMethods.jobCancel.bind(@)(d._id, options)

          console.log "jobCancel succeeded"
          return true
        else
          console.warn "jobCancel failed"
      else
        console.warn "jobCancel: something's wrong with done: #{id}", runId, err
      return false

    jobRestart: (id, options) ->
      check id, Meteor.Collection.ObjectID
      check options, Match.Optional
        retries: Match.Optional(Match.Where validIntGTEOne)
        dependents: Match.Optional Boolean
      options ?= {}
      options.retries ?= 1
      options.dependents ?= true
      console.log "Restarting: #{id}"
      if id
        time = new Date()
        num = @update(
          {
            _id: id
            status:
              $in: Job.jobStatusRestartable
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
              retries: options.retries
            $push:
              log:
                time: time
                runId: null
                level: 'info'
                message: "Job Restarted"
          }
        )
        if num is 1
          # Cancel the entire tree of dependents
          console.log "Restarting deps"
          doc = @findOne(
            {
              _id: id
            }
            {
              fields:
                depends: 1
            }
          )
          if doc
            dependQuery = [
              _id:
                $in: doc.depends
            ]
            if options.dependents
              dependQuery.push
                depends:
                  $all: [ id ]

            cursor = @find(
              {
                status:
                  $in: Job.jobStatusRestartable
                $or: dependQuery
              }
              {
                fields:
                  _id: 1
              }
            ).forEach (d) =>
              console.log "restarting #{d._id}"
              serverMethods.jobRestart.bind(@)(d._id, options)
          console.log "jobRestart succeeded"
          return true
        else
          console.warn "jobRestart failed"
      else
        console.warn "jobRestart: something's wrong with done: #{id}", runId, err
      return false

    # Job creator methods

    jobSave: (doc, options) ->
      check doc, validJobDoc()
      check options, Match.Optional {}
      options ?= {}
      time = new Date()
      if doc._id
        num = @update(
          {
            _id: doc._id
            status: { $in: Job.jobStatusPausable }
            runId: null
          }
          {
            $set:
              data: doc.data
              retries: doc.retries
              retryWait: doc.retryWait
              repeats: doc.repeats
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
                message: "Job Resubmitted"
          }
        )
        if num
          return doc._id
        else
          return null
      else
        if doc.repeats is Job.forever
          # If this is unlimited repeating job, then cancel any existing jobs of the same type
          @find(
            {
              type: doc.type
              status:
                $in: Job.jobStatusCancellable
            }
          ).forEach (d) => serverMethods.jobCancel.bind(@)(d._id, {})
        doc.log.push
          time: time
          runId: null
          level: 'info'
          message: "Job Submitted"
        return @insert doc

    # Worker methods

    jobProgress: (id, runId, completed, total, options) ->
      check id, Meteor.Collection.ObjectID
      check runId, Meteor.Collection.ObjectID
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
      check id, Meteor.Collection.ObjectID
      check runId, Meteor.Collection.ObjectID
      check message, String
      check options, Match.Optional
        level: Match.Optional(Match.Where validLogLevel)
      options ?= {}
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
                level: options.level ? 'default'
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

    jobDone: (id, runId, options) ->
      check id, Meteor.Collection.ObjectID
      check runId, Meteor.Collection.ObjectID
      check options, Match.Optional {}
      options ?= {}
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
            $push:
              log:
                time: time
                runId: runId
                message: "Job Completed Successfully"
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
                  level: 'info'
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

    jobFail: (id, runId, err, options) ->
      check id, Meteor.Collection.ObjectID
      check runId, Meteor.Collection.ObjectID
      check err, String
      check options, Match.Optional {}
      options ?= {}
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
                level: if newStatus is 'failed' then 'danger' else 'warning'
                message: "Job Failed with Error #{err}"
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
      @stopped = true

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
      for methodName, methodFunc of methods
        console.log "Generating Method: #{root}_#{methodName}"
        methodsOut["#{root}_#{methodName}"] = @_method_wrapper(methodName, methodFunc.bind(@))
      return methodsOut

    jobLogLevels: Job.jobLogLevels
    jobPriorities: Job.jobPriorities
    jobStatuses: Job.jobPriorities
    jobStatusCancellable: Job.jobStatusCancellable
    jobStatusPausable: Job.jobStatusPausable
    jobStatusRemovable: Job.jobStatusRemovable
    jobStatusRestartable: Job.jobStatusRestartable

    createJob: (params...) -> new Job @root, params...

    getJob: (params...) -> Job.getJob @root, params...

    getWork: (params...) -> Job.getWork @root, params...

    startJobs: (params...) -> Job.startJobs @root, params...

    stopJobs: (params...) -> Job.stopJobs @root, params...

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
      if @stopped
        console.log "Run status: STOPPED"
        return
      else
        console.log "Run status: Running..."

        time = new Date()
        num = @update(
          {
            status: "waiting"
            after:
              $lte: time
            depends:
              $size: 0
          }
          {
            $set:
              status: "ready"
              updated: time
            $push:
              log:
                time: time
                runId: null
                level: 'success'
                message: "Promoted to ready"
          }
          {
            multi: true
          }
        )
        console.log "Ready fired: #{num} jobs promoted"

        exptime = new Date( time.valueOf() - @expireAfter )
        console.log "checking for expiration times before", exptime

        num = @update(
          {
            status: "running"
            updated:
              $lte: exptime
            retries:
              $gt: 0
          }
          {
            $set:
              status: "ready"
              runId: null
              updated: time
              progress:
                completed: 0
                total: 1
                percent: 0
            $push:
              log:
                time: time
                runId: null
                level: 'warning'
                message: "Expired to retry"
          }
          {
            multi: true
          }
        )
        console.log "Expired #{num} dead jobs, waiting to run"

        cursor = @find(
          {
            status: "running"
            updated:
              $lte: exptime
            retries: 0
          }
        )
        num = cursor.count()
        cursor.forEach (d) =>
          id = d._id
          n = @update(
            {
              _id: id
              status: "running"
              updated:
                $lte: exptime
              retries: 0
            }
            {
              $set:
                status: "failed"
                runId: null
                updated: time
                progress:
                  completed: 0
                  total: 1
                  percent: 0
              $push:
                log:
                  time: time
                  runId: null
                  level: 'danger'
                  message: "Expired to failure"
            }
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
                    level: 'danger'
                    message: "Job Failed due to failure of dependancy #{id} by expiration"
              }
              {
                multi: true
              }
            )
            console.log "Failed #{n} dependent jobs"

        console.log "Expired #{num} dead jobs, failed"
