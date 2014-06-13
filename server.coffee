############################################################################
#     Copyright (C) 2014 by Vaughn Iverson
#     jobCollection is free software released under the MIT/X11 license.
#     See included LICENSE file for details.
############################################################################

if Meteor.isServer

  ###############################################################
  # jobCollection server DDP methods

  ################################################################
  ## jobCollection server class

  class JobCollection extends Meteor.Collection

    constructor: (@root = 'queue', options = {}) ->
      unless @ instanceof JobCollection
        return new JobCollection(@root, options)

      # Call super's constructor
      super @root + '.jobs', { idGeneration: 'MONGO' }
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
        methodsOut["#{root}_#{methodName}"] = @_method_wrapper(methodName, methodFunc.bind(@))
      return methodsOut

    jobLogLevels: Job.jobLogLevels
    jobPriorities: Job.jobPriorities
    jobStatuses: Job.jobStatuses
    jobStatusCancellable: Job.jobStatusCancellable
    jobStatusPausable: Job.jobStatusPausable
    jobStatusRemovable: Job.jobStatusRemovable
    jobStatusRestartable: Job.jobStatusRestartable

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
        throw new Error "logStream may only be set once per jobCollection startup/shutdown cycle"

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
      if typeof milliseconds is 'number' and milliseconds > 1000
        if @interval
          Meteor.clearInterval @interval
        @interval = Meteor.setInterval @_poll.bind(@), milliseconds
      else
        console.warn "jobCollection.promote: invalid timeout or limit: #{@root}, #{milliseconds}, #{limit}"

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
