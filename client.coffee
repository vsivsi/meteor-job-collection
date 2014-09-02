############################################################################
#     Copyright (C) 2014 by Vaughn Iverson
#     job-collection is free software released under the MIT/X11 license.
#     See included LICENSE file for details.
############################################################################

if Meteor.isClient

  ################################################################
  ## job-collection client class

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

      @logConsole = false

      Meteor.methods(@_generateMethods share.serverMethods)

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

    _method_wrapper: (method, func) ->

      toLog = (userId, message) =>
        if @logConsole
          console.log "#{new Date()}, #{userId}, #{method}, #{message}\n"

      # Return the wrapper function that the Meteor method will actually invoke
      return (params...) ->
        user = this.userId ? "[UNAUTHENTICATED]"
        toLog user, "params: " + JSON.stringify(params)
        retval = func(params...)
        toLog user, "returned: " + JSON.stringify(retval)
        return retval

    _generateMethods: (methods) ->
      methodsOut = {}
      for methodName, methodFunc of methods
        methodsOut["#{@root}_#{methodName}"] = @_method_wrapper(methodName, methodFunc.bind(@))
      return methodsOut
