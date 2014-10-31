/***************************************************************************
###     Copyright (C) 2014 by Vaughn Iverson
###     job-collection is free software released under the MIT/X11 license.
###     See included LICENSE file for details.
***************************************************************************/

Package.describe({
   summary: "A persistent and reactive job queue for Meteor, supporting distributed workers that can run anywhere",
   name: 'vsivsi:job-collection',
   version: '0.0.18',
   git: 'https://github.com/vsivsi/meteor-job-collection.git'
});

Npm.depends({});

Package.onUse(function(api) {
   api.use('coffeescript@1.0.3', ['server','client']);
   api.addFiles('job/src/job_class.coffee', ['server','client']);
   api.addFiles('shared.coffee', ['server','client']);
   api.addFiles('server.coffee', 'server');
   api.addFiles('client.coffee', 'client');
   api.export('Job');
   api.export('JobCollection');
});

Package.onTest(function (api) {
  api.use(['vsivsi:job-collection', 'coffeescript', 'tinytest', 'test-helpers'], ['server','client']);
  api.addFiles('job_collection_tests.coffee', ['server', 'client']);
});
