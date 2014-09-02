############################################################################
#     Copyright (C) 2014 by Vaughn Iverson
#     job-collection is free software released under the MIT/X11 license.
#     See included LICENSE file for details.
############################################################################

if Meteor.isServer

  ###############################################################
  # job-collection server DDP methods

  ################################################################
  ## job-collection server class

  class JobCollection extends Meteor.Collection

    constructor: (@root = 'queue', options = {}) ->
      unless @ instanceof JobCollection
        return new JobCollection(@root, options)

      options.idGeneration ?= 'STRING'  # or 'MONGO'
      options.noCollectionSuffix ?= false

      collectionName = @root

      unless options.noCollectionSuffix
        collectionName += '.jobs'

      # Call super's constructor
      super collectionName, { idGeneration: options.idGeneration }

      @stopped = true

      # No client mutators allowed
      JobCollection.__super__.deny.bind(@)
        update: () => true
        insert: () => true
        remove: () => true

      @promote()

      @logStream = null

      @allows = {}
      @denys = {}

      # Initialize allow/deny lists for permission levels and ddp methods
      for level in @ddpPermissionLevels.concat @ddpMethods
        @allows[level] = []
        @denys[level] = []

      Meteor.methods(@_generateMethods share.serverMethods)

    _method_wrapper: (method, func) ->

      toLog = (userId, message) =>
        @logStream?.write "#{new Date()}, #{userId}, #{method}, #{message}\n"

      myTypeof = (val) ->
        type = typeof val
        type = 'array' if type is 'object' and type instanceof Array
        return type

      permitted = (userId, params) =>

        performTest = (tests) =>
          result = false
          for test in tests when result is false
            result = result or switch myTypeof(test)
              when 'array' then userId in test
              when 'function' then test(userId, method, params)
              else false
          return result

        performAllTests = (allTests) =>
          result = false
          for t in @ddpMethodPermissions[method] when result is false
            result = result or performTest(allTests[t])
          return result

        return not performAllTests(@denys) and performAllTests(@allows)

      # Return the wrapper function that the Meteor method will actually invoke
      return (params...) ->
        user = this.userId ? "[UNAUTHENTICATED]"
        unless this.connection
          user = "[SERVER]"
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
        methodsOut["#{@root}_#{methodName}"] = @_method_wrapper(methodName, methodFunc.bind(@))
      return methodsOut

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

    setLogStream: (writeStream = null) ->
      if @logStream
        throw new Error "logStream may only be set once per job-collection startup/shutdown cycle"

      @logStream = writeStream
      unless not @logStream? or
             @logStream.write? and
             typeof @logStream.write is 'function' and
             @logStream.end? and
             typeof @logStream.end is 'function'
        throw new Error "logStream must be a valid writable node.js Stream"

    # Register application allow rules
    allow: (allowOptions) ->
      @allows[type].push(func) for type, func of allowOptions when type of @allows

    # Register application deny rules
    deny: (denyOptions) ->
      @denys[type].push(func) for type, func of denyOptions when type of @denys

    promote: (milliseconds = 15*1000) ->
      if typeof milliseconds is 'number' and milliseconds > 0
        if @interval
          Meteor.clearInterval @interval
        @interval = Meteor.setInterval @_poll.bind(@), milliseconds
      else
        console.warn "jobCollection.promote: invalid timeout: #{@root}, #{milliseconds}"

    _poll: () ->
      if @stopped
        return

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
