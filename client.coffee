############################################################################
#     Copyright (C) 2014-2015 by Vaughn Iverson
#     job-collection is free software released under the MIT/X11 license.
#     See included LICENSE file for details.
############################################################################

if Meteor.isClient

  ################################################################
  ## job-collection client class

  class JobCollection extends share.JobCollectionBase

    constructor: (root = 'queue', options = {}) ->
      unless @ instanceof JobCollection
        return new JobCollection(root, options)

      # Call super's constructor
      super root, options

      @logConsole = false

      Meteor.methods @_generateMethods()

    _methodWrapper: (method, func) ->

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
