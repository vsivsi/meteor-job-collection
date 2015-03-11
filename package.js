/***************************************************************************
###     Copyright (C) 2014-2015 by Vaughn Iverson
###     job-collection is free software released under the MIT/X11 license.
###     See included LICENSE file for details.
***************************************************************************/

Package.describe({
   summary: "A persistent and reactive job queue for Meteor, supporting distributed workers that can run anywhere",
   name: 'vsivsi:job-collection',
   version: '1.0.0',
   git: 'https://github.com/vsivsi/meteor-job-collection.git'
});

Npm.depends({});

Package.onUse(function(api) {
   api.use('coffeescript@1.0.5', ['server','client']);
   api.use('mongo@1.0.11', ['server','client']);
   api.use('check@1.0.4', ['server','client']);
   api.addFiles('job/src/job_class.coffee', ['server','client']);
   api.addFiles('shared.coffee', ['server','client']);
   api.addFiles('server.coffee', 'server');
   api.addFiles('client.coffee', 'client');
   api.export('Job');
   api.export('JobCollection');
});

Package.onTest(function (api) {
  api.use(['vsivsi:job-collection', 'coffeescript', 'tinytest', 'test-helpers', 'check', 'ddp'], ['server','client']);
  api.use('ddp@1.0.14', 'client');
  api.addFiles('job_collection_tests.coffee', ['server', 'client']);
});
