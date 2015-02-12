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
      @isSimulation = true

      Meteor.methods @_generateMethods()

    _toLog: (userId, method, message) =>
      if @logConsole
        console.log "#{new Date()}, #{userId}, #{method}, #{message}\n"