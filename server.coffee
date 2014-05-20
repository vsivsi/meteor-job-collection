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

      @logStream = options.logStream ? null

      @permissions = options.permissions ? { allow: true, deny: false }

      Meteor.methods(@_generateMethods share.serverMethods)

    _method_wrapper: (method, func) ->

      toLog = (userId, message) =>
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

    makeJob: (params...) -> Job.makeJob @root, params...

    getJobs: (params...) -> Job.getJobs @root, params...

    cancelJobs: (params...) -> Job.cancelJobs @root, params...

    pauseJobs: (params...) -> Job.pauseJobs @root, params...

    resumeJobs: (params...) -> Job.resumeJobs @root, params...

    restartJobs: (params...) -> Job.restartJobs @root, params...

    removeJobs: (params...) -> Job.removeJobs @root, params...

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
