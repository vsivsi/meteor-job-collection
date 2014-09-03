/***************************************************************************
###     Copyright (C) 2014 by Vaughn Iverson
###     jobCollection is free software released under the MIT/X11 license.
###     See included LICENSE file for details.
***************************************************************************/

Package.describe({
   name: 'vsivsi:meteor-job-collection',
   summary: "A persistent and reactive job queue for Meteor, supporting distributed workers that can run anywhere"
});

Npm.depends({});

Package.on_use(function(api) {
  api.versionsFrom("METEOR@0.9.0");
   api.use('coffeescript', ['server','client']);
   api.add_files('job/src/job_class.coffee', ['server','client']);
   api.add_files('shared.coffee', ['server','client']);
   api.add_files('server.coffee', 'server');
   api.add_files('client.coffee', 'client');
   api.export('Job');
   api.export('JobCollection');
});

Package.on_test(function (api) {
  api.use('coffeescript', ['server','client']);
  api.use(["vsivsi:meteor-job-collection",'tinytest', 'test-helpers'], ['server','client']);
  api.add_files('job_collection_tests.coffee', ['server', 'client']);
});
