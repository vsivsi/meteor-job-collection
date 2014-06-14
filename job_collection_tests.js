/***************************************************************************
###     Copyright (C) 2014 by Vaughn Iverson
###     jobCollection is free software released under the MIT/X11 license.
###     See included LICENSE file for details.
***************************************************************************/

function bind_env(func) {
  if (typeof func == 'function') {
    return Meteor.bindEnvironment(func, function (err) { throw err });
  }
  else {
    return func;
  }
}

var subWrapper = function (sub, func) {
  return function(test, onComplete) {
    if (Meteor.isClient) {
      Deps.autorun(function () {
        if (sub.ready()) {
          func(test, onComplete);
        }
      });
    } else {
      func(test, onComplete);
    }
  };
};

var defaultColl = new JobCollection();

Tinytest.add('JobCollection default constructor', function(test) {
  test.instanceOf(defaultColl, JobCollection, "JobCollection constructor failed");
  test.equal(defaultColl.root, 'queue', "default root isn't 'queue'");
  if (Meteor.isServer) {
    test.equal(defaultColl.stopped, true, "isn't initially stopped");
    test.equal(defaultColl.logStream, null, "Doesn't have a logStream");
    test.instanceOf(defaultColl.allows, Object, "allows isn't an object");
    test.equal(Object.keys(defaultColl.allows).length, 19, "allows not properly initialized");
    test.instanceOf(defaultColl.denys, Object, "denys isn't an object");
    test.equal(Object.keys(defaultColl.denys).length, 19, "denys not properly initialized");
  } else {
    test.equal(defaultColl.logConsole, false, "Doesn't have a logConsole");
  }
});


