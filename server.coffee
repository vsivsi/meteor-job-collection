############################################################################
#     Copyright (C) 2014-2015 by Vaughn Iverson
#     job-collection is free software released under the MIT/X11 license.
#     See included LICENSE file for details.
############################################################################

if Meteor.isServer

  ################################################################
  ## job-collection server class

  class JobCollection extends share.JobCollectionBase

    constructor: (root = 'queue', options = {}) ->
      unless @ instanceof JobCollection
        return new JobCollection(root, options)

      # Call super's constructor
      super root, options

      @stopped = true

      # No client mutators allowed
      JobCollection.__super__.deny.bind(@)
        update: () => true
        insert: () => true
        remove: () => true

      # Default indexes
      @._ensureIndex { type : 1, status : 1 }

      @promote()

      @logStream = null

      @allows = {}
      @denys = {}

      # Initialize allow/deny lists for permission levels and ddp methods
      for level in @ddpPermissionLevels.concat @ddpMethods
        @allows[level] = []
        @denys[level] = []

      # If a ddp option is given, then this JobCollection is actually hosted
      # remotely, so don't establish local and remotely callable server methods in that case
      unless options.ddp?
        @isSimulation = false
        localMethods = @_generateMethods()
        Job._localServerMethods ?= {}
        Job._localServerMethods[methodName] = methodFunction for methodName, methodFunction of localMethods
        Job._setDDPApply (name, params, cb) ->
          if cb?
            Meteor.setTimeout (() -> cb null, Job._localServerMethods[name].apply(this, params)), 0
          else
            Job._localServerMethods[name].apply(this, params)
        Meteor.methods localMethods
      else
        @isSimulation = true
        options.ddp.methods @_generateMethods()

    _toLog: (userId, method, message) =>
      @logStream?.write "#{new Date()}, #{userId}, #{method}, #{message}\n"

    _methodWrapper: (method, func) ->

      toLog = @_toLog

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
        toLog user, method, "params: " + JSON.stringify(params)
        unless this.connection and not permitted(this.userId, params)
          retval = func(params...)
          toLog user, method, "returned: " + JSON.stringify(retval)
          return retval
        else
          toLog this.userId, method, "UNAUTHORIZED."
          throw new Meteor.Error 403, "Method not authorized", "Authenticated user is not permitted to invoke this method."

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

    # Hook function to sanitize documents before validating them in getWork() and getJob()
    scrub: (job) ->
      job

    promote: (milliseconds = 15*1000) ->
      if typeof milliseconds is 'number' and milliseconds > 0
        if @interval
          Meteor.clearInterval @interval
        @interval = Meteor.setInterval @_promote_jobs.bind(@), milliseconds
      else
        console.warn "jobCollection.promote: invalid timeout: #{@root}, #{milliseconds}"

    _promote_jobs: (ids = []) ->
      if @stopped
        return

      time = new Date()

      query =
        status: "waiting"
        after:
          $lte: time
        depends:
          $size: 0

      # Support updating a single document
      if ids.length > 0
        query._id =
          $in: ids

      num = @update(
        query
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
