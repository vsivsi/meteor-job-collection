/***************************************************************************
###     Copyright (C) 2014 by Vaughn Iverson
###     jobCollection is free software released under the MIT/X11 license.
###     See included LICENSE file for details.
***************************************************************************/

Package.describe({
  name: 'jobCollection',
  summary: "WIP: Reactive and distributed job queue for Meteor.js using MongoDB"
});

Npm.depends({});

Package.on_use(function(api) {
  api.use('coffeescript', ['server','client']);
  api.add_files('job/src/job_class.coffee', ['server','client']);
  api.add_files('shared.coffee', ['server','client']);
  api.add_files('server.coffee', 'server');
  api.add_files('client.coffee', 'client');
  api.export('Job');
  api.export('JobCollection');
});

Package.on_test(function (api) {

});
