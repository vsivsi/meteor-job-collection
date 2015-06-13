############################################################################
#     Copyright (C) 2014-2015 by Vaughn Iverson
#     job-collection is free software released under the MIT/X11 license.
#     See included LICENSE file for details.
############################################################################

if Meteor.isClient

  # This is a polyfill for bind(), added to make phantomjs 1.9.7 work
  unless Function.prototype.bind
    Function.prototype.bind = (oThis) ->
       if typeof this isnt "function"
          # closest thing possible to the ECMAScript 5 internal IsCallable function
          throw new TypeError("Function.prototype.bind - what is trying to be bound is not callable")

       aArgs = Array.prototype.slice.call arguments, 1
       fToBind = this
       fNOP = () ->
       fBound = () ->
          func = if (this instanceof fNOP and oThis) then this else oThis
          return fToBind.apply(func, aArgs.concat(Array.prototype.slice.call(arguments)))

       fNOP.prototype = this.prototype
       fBound.prototype = new fNOP()
       return fBound

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

      unless options.connection?
        Meteor.methods @_generateMethods()
      else
        options.connection.methods @_generateMethods()

    _toLog: (userId, method, message) =>
      if @logConsole
        console.log "#{new Date()}, #{userId}, #{method}, #{message}\n"
