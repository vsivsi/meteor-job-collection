# job-collection

## Intro

job-collection is a powerful and easy to use job manager designed and built for [Meteor.js](http://meteor.com).

It solves the following problems (and more):

* Schedule jobs to run (and repeat) in the future, persisting across server restarts
* Move work out of Meteor's single threaded event-loop
* Enable work on computationally expensive jobs to run anywhere, on any number of machines
* Track jobs and their progress, and automatically retry failed jobs
* Easily build an admin UI to manage all of the above using Meteor's reactivity and UI goodness

**Note:** This Package remains experimental until v0.1.0 is released (which will be soon). The API methods described herein are maturing, but they may still change. If you have feature suggestions or other feedback, now is the time to bring it to my attention. If you want to live dangerously, development is occuring on the `dev` branch.

**Note:** job-collection was formerly called jobCollection, but changes in the packaging system since Meteor 0.9 do not permit uppercase letters in package names, so the name had to change.

**Note:** If you are looking for a Meteor v0.8.x compatible version of this package, please see the `meteor-0.8-compat` branch. It has the same functionality as the `master` branch, but with old-skool Meteor v0.8.x package compatibility. Note, there will be no further development on this version of the package.

## Table of Contents

- [Quick example](#user-content-quick-example)
- [Design](#user-content-design)
- [Installation](#user-content-installation)
- [Use](#user-content-use)
  - [Security](#user-content-security)
  - [Performance](#user-content-performance)
  - [Logging](#user-content-logging)
- [JobCollection API](#user-content-jobcollection-api)
- [Job API](#user-content-job-api)
- [JobQueue API](#user-content-jobqueue-api)
- [Job document data models](#user-content-job-document-data-models)
- [DDP Method reference](#user-content-ddp-method-reference)

### Quick example

The code snippets below show a Meteor server that creates a `JobCollection`, Meteor client code that subscribes to it and creates a new job, and a pure node.js program that can run *anywhere* and work on such jobs.

```js
///////////////////
// Server
if (Meteor.isServer) {

  var myJobs = JobCollection('myJobQueue');
  myJobs.allow({
    // Grant full permission to any authenticated user
    admin: function (userId, method, params) {
      return (userId ? true : false);
    }
  });

  Meteor.startup(function () {
    // Normal Meteor publish call, the server always
    // controls what each client can see
    Meteor.publish('allJobs', function () {
      return myJobs.find({});
    });

    // Start the myJobs queue running
    return myJobs.startJobServer();
  });
}
```

Alright, the server is set-up and running, now let's add some client code to create/manage a job.

```js
///////////////////
// Client
if (Meteor.isClient) {

  var myJobs = JobCollection('myJobQueue');

  Meteor.startup(function () {
     Meteor.subscribe('allJobs');

     // Because of the server settings, the code below will
     // only work if the client is authenticated.
     // On the server, all of it would run unconditionally.

     // Create a job:
     var job = myJobs.createJob('sendEmail', // type of job
       // Job data that you define, including anything the job
       // needs to complete. May contain links to files, etc...
       {
         address: 'bozo@clowns.com',
         subject: 'Critical rainbow hair shortage',
         message: 'LOL; JK, KThxBye.'
       }
     );

     // Set some properties of the job and then submit it
     job.priority('normal')
       .retry({ retries: 5,
         wait: 15*60*1000 })  // 15 minutes between attempts
       .delay(60*60*1000)     // Wait an hour before first try
       .save();               // Commit it to the server

     // Now that it's saved, this job will appear as a document
     // in the myJobs Collection, and will reactively update as
     // its status changes, etc.

     // Any job document from myJobs can be turned into a Job object
     job = myJobs.createJob(myJobs.findOne({}));

     // Or a job can be fetched from the server by _id
     myJobs.getJob(_id, function (err, job) {
       // If successful, job is a Job object corresponding to _id
       // With a job object, you can remotely control the
       // job's status (subject to server allow/deny rules)
       // Here are some examples:
       job.pause();
       job.cancel();
       job.remove();
       // etc...
     });
  });
}
```

**Q:** Okay, that's cool, but where does the actual work get done?

**A:** Anywhere you want!

 job-collection is extremely flexible in where the work can get done; from workers that only run on the Meteor server to hundreds of node.js workers running on a cluster or in the cloud. In some cases work can even be done within properly authenticated Meteor clients.

Below is a pure node.js program that can obtain jobs from the server above and "get 'em done".
Powerfully, this can be run ***anywhere*** that has node.js and can connect to the server. The secret sauce here is the [meteor-job npm package](https://www.npmjs.org/search?q=meteor-job), which is fully interoperable with job-collection.

*NOTE!* Worker code very similar to what is shown below (without all of the DDP setup) can also run on the Meteor server or even in a Meteor client. Everything before the call to `Job.processJobs()` is just code to connect and authenticate a pure node.js script with a Meteor server.

```js
///////////////////
// node.js Worker
var DDP = require('ddp');
var DDPlogin = require('ddp-login');
var Job = require('meteor-job');

// `Job` here has essentially the same API as JobCollection on Meteor.
// In fact, job-collection is built on top of the 'meteor-job' npm package!

// Setup the DDP connection
var ddp = new DDP({
  host: "meteor.mydomain.com",
  port: 3000,
  use_ejson: true
});

// Connect Job with this DDP session
Job.setDDP(ddp);

// Open the DDP connection
ddp.connect(function (err) {
  if (err) throw err;
  // Call below will prompt for email/password if an
  // authToken isn't available in the process environment
  DDPlogin(ddp, function (err, token) {
    if (err) throw err;
    // We're in!
    // Create a worker to get sendMail jobs from 'myJobQueue'
    // This will keep running indefinitely, obtaining new work
    // from the server whenever it is available.
    // Note: If this worker was running within the Meteor environment, 
    // Then only the call below is necessary to setup a worker!
    var workers = Job.processJobs('myJobQueue', 'sendEmail',
      function (job, cb) {
        // This will only be called if a
        // 'sendEmail' job is obtained
        var email = job.data; // Only one email per job
        sendEmail(email.address, email.subject, email.message,
          function(err) {
            if (err) {
              job.log("Sending failed with error" + err,
                {level: 'warning'});
              job.fail("" + err);
            } else {
              job.done();
            }
            // Be sure to invoke the callback
            // when work on this job has finished
            cb();
          }
        );
      }
    );
  });
});
```

### Design

The design of job-collection is heavily influenced by [Kue](https://github.com/LearnBoost/kue) and to a lesser extent by the [Maui Cluster Scheduler](https://en.wikipedia.org/wiki/Maui_Cluster_Scheduler). However, unlike Kue's use of Redis Pub/Sub and an HTTP API, job-collection uses MongoDB, Meteor, and Meteor's DDP protocol to provide persistence, reactivity, and secure remote access.

As the name implies, a `JobCollection` looks and acts like a Meteor Collection because under the hood it actually is one. However, other than `.find()` and `.findOne()`, most accesses to a `JobCollection` happen via the easy to use API on `Job` objects. Most `Job` API calls are transformed internally to Meteor [Method](http://docs.meteor.com/#methods_header) calls. This is cool because the underlying `Job` class is implemented as pure Javascript that can run in both the Meteor server and client environments, and most significantly as pure node.js code running independently from Meteor (as shown in the example code above).

## Installation

To add to your project, run:

    meteor add vsivsi:job-collection

The package exposes a global object `JobCollection` on both client and server.

To run tests (using Meteor tiny-test) run from within the `job-collection` subdirectory:

    meteor test-packages ./

Load `http://localhost:3000/` and the tests should run in your browser and on the server.

A basic sample application that implements a basic image gallery with upload/download support and automatic generation of thumbnail images is available. It also implements a basic job manager UI that allows control of both individual jobs and changes to the entire collection at once.  It is available here: https://github.com/vsivsi/meteor-file-job-sample-app

## Use

job-collections are backed by [Meteor Collections](http://docs.meteor.com/#collections) and may be used in similar ways. `.find()` and `.findOne()` work as you would expect and are fully reactive on the client just as with a normal collection.

Other than the find methods mentioned above, interactions with a job collection occur using the `JobCollection`, `Job` and `JobQueue` APIs documented below. The Job document model used in a job collection is fully specified, maintained and enforced by the APIs.

Meteor clients are automatically denied permission to directly `insert`, `update` or `remove` jobs from a job collection. To accomplish these types of tasks, a client must use the provided APIs, subject to permissions set by specific allow/deny rules on the job collection. Servers retain access to the standard `insert`, `update` or `remove` methods, but should avoid using them unless absolutely necessary, favoring the job collection APIs to perform various tasks.

It is also possible (and highly useful!) to write your own clients outside of Meteor as vanilla node.js programs using the `meteor-job` [npm package](https://www.npmjs.org/package/meteor-job), which is actually used by job-collection internally, and implements essentially identical functionality via the same interfaces.

### Security

Securing a job collection is done using mechanisms that will be familiar to anyone who has used the [Meteor `publish` and `subscribe` mechanism](http://docs.meteor.com/#publishandsubscribe) and [Meteor Collection allow/deny rules](http://docs.meteor.com/#allow).

For a client to have access to perform `find()` operations on a job collection, the server must publish the collection and the client must subscribe to it. This works identically to normal Meteor collections.

Compared to vanilla Meteor collections, job-collections have a  different set of remote methods with specific security implications. Where the allow/deny methods on a Meteor collection take functions to grant permission for `insert`, `update` and `remove`, job-collection has more functionality to secure and configure.

There are currently over a dozen Meteor methods defined by each job-collection. In many cases it will be most convenient to write allow/deny rules to one of the four predefined permission groups: `admin`, `manager`, `creator` and `worker`. These defined roles separate security concerns and permit you to efficiently add allow/deny rules for groups of functions that various client functionalities are likely to need. Where these roles do not meet the requirements of a specific project, each remote method can also be individually secured with custom allow/deny rules.

### Performance

The performance of job-collection will be almost entirely dependant on the speed of the MongoDB server it is hosted on.
By default job-collection creates these indexes in the underlying database:
```js
jc._ensureIndex({ type : 1, status : 1 });
```
If you anticipate having large job collections (ie. with over 1000 jobs at a time) and you will be doing custom queires on the database, you will want to create appropriate additional indexes to ensure that your application performs well.

### Logging

The server can easily log all activity (both successes and failures) on a job collection by passing any valid node.js writable Stream to `jc.setLogStream(writeStream)`.

## JobCollection API

### jc = new JobCollection([name], [options]) - Anywhere
#### Creates a new JobCollection

Creating a new `JobCollection` is similar to creating a new Meteor Collection. You simply specify a name (which defaults to `"queue"`). On the server there are some additional methods you will probably want to invoke on the returned object to configure it further.

`options`:

* `noCollectionSuffix` -- If `true`, `'.jobs'` won't be appended to the collection name. Default: `false`
* In addition, JobCollection supports the same options as Meteor [Mongo.Collection](http://docs.meteor.com/#/full/mongo_collection)

For security and simplicity the traditional client allow/deny rules for Meteor collections are preset to deny all direct client `insert`, `update` and `remove` type operations on a `JobCollection`. This effectively channels all remote activity through the `JobCollection` DDP methods, which may be secured using allow/deny rules specific to `JobCollection`. See the documentation for `jc.allow()` and `jc.deny()` for more information.

```js
// the "new" is optional
jc = JobCollection('defaultJobCollection');
```

### jc.setLogStream(writeStream) - Server only
#### Sets where the job collection method invocation log will be written

You can log everything that happens to a job collection on the server by providing any valid writable stream. You may only call this once, unless you first call `jc.shutdown()`, which will automatically close the existing `logStream`.

```js
// Log everything to stdout
jc.setLogStream(process.stdout);
```

### jc.logConsole - Client only
#### Member variable that turns on DDP method call logging to the console

```js
jc.logConsole = false  // Default. Do not log method calls to the client console
```

### jc.promote([milliseconds]) - Server only
#### Sets time between checks for delayed jobs that are now ready to run

`jc.promote()` may be called at any time to change the polling rate. job-collection must poll for this operation because it is time that is changing, not the contents of the database, so there are no database updates to listen for.

```js
jc.promote(15*1000);  // Default: 15 seconds
```

Note: if you are running multiple Meteor instances that share access to a single job collection, you can set the time each instance waits to promote to `N * milliseconds`, where `N` is the number of Meteor instances. The instances will each take turns promoting jobs at 1/Nth of the desired rate.

### jc.allow(options) - Server only
#### Allow remote execution of specific job-collection methods

By default no remote operations are allowed, and in this configuration job-collection exists only as a server-side service; with the creation, management and execution of all jobs dependent on server-side Meteor code.

The opposite extreme is to allow any remote client to perform any action. Obviously this is totally insecure, but is perhaps valuable for early development stages on a local firewalled network.

```js
// Allow any remote client (Meteor client or
// node.js application) to perform any action
jc.allow({
  // The "admin" below represents
  // the grouping of all remote methods
  admin: function (userId, method, params) {
    return true;
  }
});
```

If this seems a little reckless (and it should), then here is how you can grant admin rights specifically to an single authenticated Meteor userId:

```js
// Allow only the authenticated "admin user" to perform any action
jc.allow({
  // Assume "adminUserId" contains the Meteor
  // userId string of an admin super-user.
  // The array below is assumed to be an array of userIds
  admin: [ adminUserId ]
});

// The array notation in the above code is a shortcut for:
var adminUsers = [ adminUserId ];
jc.allow({
  // Assume "adminUserId" contains the Meteor
  // userId string of an admin super-user.
  admin: function (userId, method, params) {
    return (userId in adminUsers);
  }
});
```

In addition to the all-encompassing `admin` method group, there are three others:

*    `manager` -- Managers can remotely manage the job collection (e.g. cancelling jobs).
*    `creator` -- Creators can remotely make new jobs to run.
*    `worker` -- Workers can get Jobs to work on and can update their status as work proceeds.

All remote methods affecting the job collection fall into at least one of the four groups, and for each client-capable API method below, the group(s) it belongs to will be noted.

In addition to the above groups, it is possible to write allow/deny rules specific to each job-collection DDP method. This is a more advanced feature and the intent is that the four permission groups described above should be adequate for many applications. The DDP methods are generally lower-level than the methods available on `Job` and they do not necessarily have a one-to-one relationship. Here's an example of how to grant permission to create new "email" jobs to a single userId:

```js
// Assumes emailCreator contains a Meteor userId
jc.allow({
  jobSave: function (userId, method, params) {
    // params[0] is the new job doc
    if ((userId === emailCreator) &&
        (params[0].type === 'email')) {
      return true;
    }
    return false;
  }
});
```

### jc.deny(options) - Server only
#### Override allow rules

This call has the same semantic relationship with `allow()` as it does in Meteor collections. If any deny rule is true, then permission for a remote method call will be denied, regardless of the status of any other allow/deny rules. This is powerful and far reaching. For example, the following code will turn off all remote access to a job collection (regardless of any other rules that may be in force):

```js
jc.deny({
  // The "admin" below represents the
  // grouping of all remote methods
  admin: function (userId, method, params) {
    return true;
  }
});
```

See the `allow` method above for more details.

### jc.startJobServer([options], [callback])
#### Starts the server job Collection.
#### Requires permission: Server, `admin`, or `startJobServer`

`options`: No options currently defined

`callback(error, result)` -- Result is true if successful.

```js
jc.startJobServer();  // Callback is optional
```

### jc.shutdownJobServer([options], [callback])
#### Stops the server job Collection.
#### Requires permission: Server, `admin`, or `shutdownJobServer`

`options`:

* `timeout`: In ms, how long until the server forcibly fails all still running jobs. Default: `60*1000` (1 minute)

`callback(error, result)` -- Result is true if successful.

```js
jc.shutdownJobServer(
  {
    timeout: 60000
  }
);  // Callback is optional
```

### jc.createJob(type, data) or jc.createJob(jobDoc) - Anywhere
#### Create a new `Job` object or make one from an existing job document

Data should be reasonably small, if worker requires a lot of data (e.g. video, image or sound files), they should be included by reference (e.g. with a URL pointing to the data, and another to where the result should be saved).

Note that this call only creates a new job object locally, it does not add it to the job collection. See documentation below for `Job` object API, and specifically `job.save()` to see how to do that.

Existing jobDocs must be valid job documents.

```js
job = jc.createJob(
  'jobType',    // type of the job
  { /* ... */ } // Data for the worker, any valid EJSON object
);

doc = jc.findOne({});
if (doc) {
  job = jc.createJob(doc);
}
```

### jc.getJob(id, [options], [callback]) - Anywhere
#### Create a job object by id from the server job Collection
#### Requires permission: Server, `admin`, `worker` or `getJob`

See documentation below for `Job` object API

Returns `undefined` if no such job exists.

`id`: -- The id of the job to get.

`options`:

* `getLog` -- If `true`, get the current log of the job. Default is `false` to save bandwidth since logs can be large.

`callback(error, result)` -- Optional only on Meteor Server with Fibers. `result` is a job object or `undefined`

```js
if (Meteor.isServer) {
  // Note, the server could also use the callback pattern in the
  // else clause below, but because of Fibers, it doesn't have to.
  job = jc.getJob(  // Job will be undefined or contain a Job object
    id,          // job id of type Match.Where(validId)
    {
      getLog: false  // Default, don't include the log information
    }
  );
  // Job may be undefined
} else {
  jc.getJob(
    id,            // job id of type Match.Where(validId)
    {
      getLog: true  // include the log information
    },
    function (err, job) {
      if (job) {
        // Here's your job
      }
    }
  );
}
```

### jc.getWork(type, [options], [callback]) - Anywhere
#### Get one or more jobs from the job collection, setting status to `'running'`
#### Requires permission: Server, `admin`, `worker` or `getWork`

`getWork` differs from `getJob` in that the status of the returned job(s) is now "running" in the job collection, and it is the responsibility of the caller to eventually call `job.done()` or `job.fail()` on each job. While running, a job will never be assigned to another worker. If unreliable workers are an issue, it is straightforward to write a recurring server job that identifies stale running jobs (whose workers have presumably died) and "autofail" them so that they may be retried by another worker.

`getWork` implements a "pull" model, where each call will return zero or more jobs depending on availability of work and the value of `maxJobs`. See `jc.processJobs()` below for a "push"-like model for automatically obtaining jobs to work on.

`options`:

* `maxJobs` -- Maximum number of jobs to get. Default `1`  If `maxJobs > 1` the result will be an array of job objects, otherwise it is a single job object, or `undefined` if no jobs were available

`callback(error, result)` -- Optional only on Meteor Server with Fibers. Result will be an array or single value depending on `options.maxJobs`.

```js
if (Meteor.isServer) {
  // Note, the server could also use the callback pattern in the
  // else clause below, but because of Fibers, it doesn't have to.
  job = jc.getWork(  // Job will be undefined or contain a Job object
    'jobType',   // type of job to request
    {
      maxJobs: 1 // Default, only get one job, returned as a single object
    }
  );
} else {
  jc.getWork(
    [ 'jobType1', 'jobType2' ]  // can request multiple types in array
    {
      maxJobs: 5 // If maxJobs > 1, result is an array of jobs
    },
    function (err, jobs) {
      // jobs contains between 0 and maxJobs jobs, depending
      // on availability, job type is available as
      if (job[0].type === 'jobType1') {
        // Work on jobType1...
      } else if (job[0].type === 'jobType2') {
        // Work on jobType2...
      } else {
        // Sadness
      }
    }
  );
}
```

### jq = jc.processJobs(type, [options], worker) - Anywhere
#### Create a new jobQueue to automatically work on jobs
#### Requires permission: Server, `admin`, `worker` or `getWork`

Asynchronously calls the worker function whenever jobs become available. See documentation below for the `JobQueue` object API for methods on the returned `jq` object.

`options:`

* `concurrency` -- Maximum number of async calls to `worker` that can be outstanding at a time. Default: `1`
* `payload` -- Maximum number of job objects to provide to each worker, Default: `1` If `payload > 1` the first parameter to `worker` will be an array of job objects rather than a single job object.
* `pollInterval` -- How often to ask the remote job Collection for more work, in ms. Default: `5000` (5 seconds)
* `prefetch` -- How many extra jobs to request beyond the capacity of all workers (`concurrency * payload`) to compensate for latency getting more work.

`worker(result, callback)`

* `result` -- either a single job object or an array of job objects depending on `options.payload`.
* `callback` -- must be eventually called exactly once when `job.done()` or `job.fail()` has been called on all jobs in result.

```js
queue = jc.processJobs(
  // Type of job to request
  // Can also be an array of job types
  'jobType',
  {
    concurrency: 4,
    payload: 1,
    pollInterval: 5000,
    prefetch: 1
  },
  function (job, callback) {
    // Only called when there is a valid job
    job.done();
    callback();
  }
);

// The job queue has methods...
queue.pause();
queue.resume();
queue.shutdown();
```

### jc.getJobs(ids, [options], [callback]) - Anywhere
#### Like `jc.getJob` except it takes an array of ids
#### Requires permission: Server, `admin`, `worker` or `getJob`
This is much more efficient than calling `jc.getJob()` in a loop because it gets Jobs from the server in batches.

### jc.pauseJobs(ids, [options], [callback]) - Anywhere
#### Like `job.pause()` except it pauses a list of jobs by id
#### Requires permission: Server, `admin`, `manager` or `jobPause`
This is much more efficient than calling `job.pause()` in a loop because it pauses jobs in batches on the server.

### jc.resumeJobs(ids, [options], [callback]) - Anywhere
#### Like `job.resume()` except it resumes a list of jobs by id
#### Requires permission: Server, `admin`, `manager` or `jobResume`
This is much more efficient than calling `job.resume()` in a loop because it resumes jobs in batches on the server.

### jc.cancelJobs(ids, [options], [callback]) - Anywhere
#### Like `job.cancel()` except it cancels a list of jobs by id
#### Requires permission: Server, `admin`, `manager` or `jobCancel`
This is much more efficient than calling `job.cancel()` in a loop because it cancels jobs in batches on the server.

### jc.restartJobs(ids, [options], [callback]) - Anywhere
#### Like `job.restart()` except it restarts a list of jobs by id
#### Requires permission: Server, `admin`, `manager` or `jobRestart`
This is much more efficient than calling `job.restart()` in a loop because it restarts jobs in batches on the server.

### jc.removeJobs(ids, [options], [callback]) - Anywhere
#### Like `job.remove()` except it removes a list of jobs by id
#### Requires permission: Server, `admin`, `manager` or `jobRemove`
This is much more efficient than calling `job.resmove()` in a loop because it removes jobs in batches on the server.

### jc.forever - Anywhere
#### Constant value used to indicate that something should repeat forever

```js
job = jc.createJob('jobType', { work: "to", be: "done" })
  .retry({ retries: jc.forever })    // Default for .retry()
  .repeat({ repeats: jc.forever });  // Default for .repeat()
```

### jc.foreverDate - Anywhere
Constant value used to indicate a future Date that will never arrive

```js
job = jc.createJob('jobQueue', 'jobType', { work: "to", be: "done" })
   .retry({ until: Job.foreverDate })    // Default for .retry()
   .repeat({ until: Job.foreverDate });  // Default for .repeat()
```

### jc.jobPriorities - Anywhere
#### Valid non-numeric job priorities

This is the mapping between the valid string priorities accepted by `job.priority()` and the numeric priority values it also uses.

```js
jc.jobPriorities = { "low": 10, "normal": 0, "medium": -5,
                     "high": -10, "critical": -15 };
```

### jc.jobStatuses - Anywhere
#### Possible states for the status of a job in the job collection

These are the seven possible states that a job can be in, illustrated below along with the relationships between the main five states (disregarding "paused" and "cancelled"):

![job states diagram](https://raw.githubusercontent.com/vsivsi/meteor-job/master/doc/normal-states.dot.cairo.png)

A somewhat more complicated-looking diagram showing the relationship between all seven states can be seen [here](https://raw.githubusercontent.com/vsivsi/meteor-job/master/doc/states.dot.cairo.png). If this looks crazy don't dispair, the relationships added by `.pause()` and `.cancel()` are pretty straightforward when viewed on their own. See `jc.jobStatusCancellable` and `jc.jobStatusPausable` below for more info.

```js
jc.jobStatuses = [ 'waiting', 'paused', 'ready', 'running',
                   'failed', 'cancelled', 'completed' ];
```

### jc.jobRetryBackoffMethods
#### Valid retry backoff methods

```js
jc.jobRetryBackoffMethods = [ 'constant', 'exponential' ];
```

### jc.jobLogLevels - Anywhere
#### Valid log levels

If these look familiar, it's because they correspond to some of the Bootstrap [context](http://getbootstrap.com/css/#helper-classes) and [alert](http://getbootstrap.com/components/#alerts) classes.

```js
jc.jobLogLevels = [ 'info', 'success', 'warning', 'danger' ];
```

### jc.jobStatusCancellable - Anywhere
#### Job status states that can be cancelled

To be cancellable, a job must currently be in one of these states. Below is a state diagram of the relationships of the "cancelled" state:

![canceled state relationships](https://raw.githubusercontent.com/vsivsi/meteor-job/master/doc/cancel-states.dot.cairo.png)

```js
jc.jobStatusCancellable = [ 'running', 'ready', 'waiting', 'paused' ];
```

### jc.jobStatusPausable - Anywhere
#### Job status states that can be paused

These are the only states that may be paused. Below is a state diagram of the relationships of the "paused" state:

![paused state relationships](https://raw.githubusercontent.com/vsivsi/meteor-job/master/doc/pause-states.dot.cairo.png).

```js
jc.jobStatusPausable = [ 'ready', 'waiting' ];
```

### jc.jobStatusRemovable - Anywhere
#### Job status states that can be removed

Only jobs in one of these states may be removed. To remove any other job, simply cancel it first.

```js
jc.jobStatusRemovable = [ 'cancelled', 'completed', 'failed' ];
```

### jc.jobStatusRestartable - Anywhere
#### Job status states that can be restarted

Only jobs in one of these terminal states may be restarted. Successfully completed jobs may be re-run using a different command (job.rerun()).

```js
jc.jobStatusRestartable = [ 'cancelled', 'failed' ];
```

### jc.ddpMethods - Anywhere
#### Array of the root names of all DDP methods used by job-collection

These are all of valid job-collection DDP method names. These are also the names of the coinciding method-specific allow/deny rules. For more information about the DDP method API see the documentaion on that topic near the end of this README.

```js
jc.ddpMethods = [ 'startJobServer', 'shutdownJobServer', 'jobRemove',
                  'jobPause', 'jobResume', 'jobCancel', 'jobRestart',
                  'jobSave', 'jobRerun', 'getWork', 'getJob',
                  'jobLog','jobProgress', 'jobDone', 'jobFail' ];
```

### jc.ddpPermissionLevels - Anywhere
#### Array of the predefined DDP method permission levels

These are the currently defined allow/deny method permission groups.

```js
jc.ddpPermissionLevels = [ 'admin', 'manager', 'creator', 'worker' ];
```

### jc.ddpMethodPermissions - Anywhere
#### Object mapping permission levels to DDP method names

This is the mapping between job-collection DDP methods and permission groups.

```js
jc.ddpMethodPermissions = {
    'startJobServer': ['startJobServer', 'admin'],
    'shutdownJobServer': ['shutdownJobServer', 'admin'],
    'jobRemove': ['jobRemove', 'admin', 'manager'],
    'jobPause': ['jobPause', 'admin', 'manager'],
    'jobResume': ['jobResume', 'admin', 'manager'],
    'jobCancel': ['jobCancel', 'admin', 'manager'],
    'jobRestart': ['jobRestart', 'admin', 'manager'],
    'jobSave': ['jobSave', 'admin', 'creator'],
    'jobRerun': ['jobRerun', 'admin', 'creator'],
    'getWork': ['getWork', 'admin', 'worker'],
    'getJob': ['getJob', 'admin', 'worker'],
    'jobLog': [ 'jobLog', 'admin', 'worker'],
    'jobProgress': ['jobProgress', 'admin', 'worker'],
    'jobDone': ['jobDone', 'admin', 'worker'],
    'jobFail': ['jobFail', 'admin', 'worker']
};
```

### jc.jobDocPattern - Anywhere
#### Object that can be used with the [Meteor check](http://docs.meteor.com/#/full/check_package) package to validate job documents

```js

if (! Match.test(job.doc, jc.jobDocPattern)) {
  // Something is wrong with this job's document!
}

```

## Job API

New `Job` objects are created using the following JobCollection API calls:

* `jc.createJob()` -- Creates a new `Job` object or makes one from a job document (as retrieved from MongoDB)
* `jc.getJob()` -- Get a `Job` object from the job collection by Id
* `jc.getJobs()` -- Get multiple `Job` objects from a job collection using an array of Ids

The methods below may be performed on `Job` objects regardless of their source. All `Job` methods may be run on the client or server.

### job.depends([dependencies]) - Anywhere
#### Adds jobs that this job depends upon (antecedents)

This job will not run until these jobs have successfully completed. Defaults to an empty array (no dependencies). Returns `job`, so it is chainable.
Added jobs must have already had `.save()` run on them, so they will have the `_id` attribute that is used to form the dependency. Calling `job.depends()` with a falsy value will clear any existing dependencies for this job.

```js
// job1 and job2 are Job objects,
// and must successfully complete before job will run
job.depends([job1, job2]);
// Clear any dependencies previously added on this job
job.depends();
```

### job.priority([priority]) - Anywhere
#### Sets the priority of this job

Can be integer numeric or one of `Job.jobPriorities`. Defaults to `'normal'` priority, which is priority `0`. Returns `job`, so it is chainable.

```js
job.priority('high');  // Maps to -10
job.priority(-10);     // Same as above
```

### job.retry([options]) - Anywhere
#### Set how failing jobs are rescheduled and retried by the job Collection

Returns `job`, so it is chainable.

`options:`

* `retries` -- Number of times to retry a failing job. Default: `Job.forever`
* `until` -- Keep retrying until this `Date`, or until the number of retries is exhausted, whichever comes first. Default: `Job.foreverDate`. Note that if you specify a value for `until` on a repeating job, it will only apply to the first run of the job. Any repeated runs of the job will use the repeat `until` value for all retries.
* `wait` -- Initial value for how long to wait between attempts, in ms. Default: `300000` (5 minutes)
* `backoff` -- Method to use in determining how to calculate wait value for each retry:
    * `'constant'`:  Always delay retrying by `wait` ms.  Default value.
    * `'exponential'`:  Delay by twice as long for each subsequent retry, e.g. `wait`, `2*wait`, `4*wait` ...

`[options]` may also be a non-negative integer, which is interpreted as `{ retries: [options] }`

Note that the above stated defaults are those when `.retry()` is explicitly called. When a new job is created, the default number of `retries` is `0`.

```js
job.retry({
  retries: 5,   // Retry 5 times,
  wait: 20000,  // waiting 20 seconds between attempts
  backoff: 'constant'  // wait constant amount of time between each retry
});
```

### job.repeat([options]) - Anywhere
#### Set how many times this job will be automatically re-run by the job Collection

Each time it is re-run, a new job is created in the job collection. This is equivalent to running `job.rerun()`. Only `'completed'` jobs are repeated. Failing jobs that exhaust their retries will not repeat. By default, if an infinitely repeating job is added to the job Collection, any existing repeating jobs of the same type will also continue to repeat.  See `option.cancelRepeats` for `job.save()` for more info on how to override this behavior. Returns `job`, so it is chainable.

`options:`

* `repeats` -- Number of times to rerun the job. Default: `Job.forever`
* `until` -- Keep repeating until this `Date`, or until the number of repeats is exhausted, whichever comes first. Default: `Job.foreverDate`
* `wait`  -- How long to wait between re-runs, in ms. Default: `300000` (5 minutes)

`[options]` may also be a non-negative integer, which is interpreted as `{ repeats: [options] }`

Note that the above stated defaults are those when `.repeat()` is explicitly called. When a new job is created, the default number of `repeats` is `0`.

```js
job.repeat({
  repeats: 5,   // Rerun this job 5 times,
  wait: 20000   // wait 20 seconds between each re-run.
});
```

### job.delay([milliseconds]) - Anywhere
#### Sets how long to wait until this job can be run

Counts from when it is initially saved to the job Collection.
Returns `job`, so it is chainable.

```js
job.delay(0);   // Do not wait. This is the default.
```

### job.after([time]) - Anywhere
#### Sets the time after which a job may be run

`time` is a date object.  It is not guaranteed to run "at" this time because there may be no workers available when it is reached. Returns `job`, so it is chainable.

```js
// Run the job anytime after right now
// This is the default.
job.after(new Date());
```

### job.log(message, [options], [callback]) - Anywhere
#### Add an entry to this job's log
#### Requires permission: Server, `admin`, `worker` or `jobLog`

May be called before a new job is saved. `message` must be a string.

`options:`

* `level`: One of `Jobs.jobLogLevels`: `'info'`, `'success'`, `'warning'`, or `'danger'`.  Default is `'info'`.
* `data`: An arbitrary object that will be written to the `data` field in the log entry.
* `echo`: Echo this log entry to the console. `'danger'` and `'warning'` level messages are echoed using `console.error()` and `console.warn()` respectively. Others are echoed using `console.log()`. If echo is `true` all messages will be echoed. If `echo` is one of the `Job.jobLogLevels` levels, only messages of that level or higher will be echoed.

`callback(error, result)` -- Result is true if logging was successful. When running as `Meteor.isServer` with fibers, for a saved object the callback may be omitted and the return value is the result. If called on an unsaved object, the result is `job` and can be chained.

```js
job.log(
  "This is a message",
  {
    level: 'warning'
    echo: true   // Default is false
  },
  function (err, result) {
    if (result) {
      // The log method worked!
    }
  }
);

var verbosityLevel = 'warning';
job.log("Don't echo this",
        { level: 'info',
          echo: verbosityLevel } );
```

### job.progress(completed, total, [options], [cb]) - Anywhere
#### Update the progress of a running job
#### Requires permission: Server, `admin`, `worker` or `jobProgress`

May be called before a new job is saved. `completed` must be a number `>= 0` and `total` must be a number `> 0` with `total >= completed`.

`options:`

* `echo`: Echo this progress update to the console using `console.log()`.

`callback(error, result)` -- Result is true if progress update was successful. When running as `Meteor.isServer` with fibers, for a saved object the callback may be omitted and the return value is the result. If called on an unsaved object, the result is `job` and can be chained.

```js
job.progress(
  50,
  100,    // Half done!
  {
    echo: true   // Default is false
  },
  function (err, result) {
    if (result) {
      // The progress method worked!
    }
  }
);
```

### job.save([options], [callback]) - Anywhere
#### Submits this job to the job Collection
#### Requires permission: Server, `admin`, `creator` or `jobSave`

Only valid if this is a new job, or if the job is currently paused in the job Collection. If the job is already saved and paused, then most properties of the job may change (but not all, e.g. the jobType may not be changed.)

`options:`
* `cancelRepeats`: If true and this job is an infinitely repeating job, will cancel any existing jobs of the same job type. This is useful for background maintenance jobs that may get added on each server restart (potentially with new parameters). Default is `false`.

`callback(error, result)` -- Result is true if save was successful. When running as `Meteor.isServer` with fibers, the callback may be omitted and the return value is the result.

```js
job.save(
  {
    // Cancel any jobs of the same type,
    // but only if this job repeats forever.
    // Default: false.
    cancelRepeats: true
  }
);
```
### job.refresh([options], [callback]) - Anywhere
#### Refreshes the current job object state with the state on the remote job-collection
#### Requires permission: Server, `admin`, `worker` or `getJob`

Note that if you subscribe to the job Collection, the job documents will stay in sync with the server automatically via Meteor reactivity.

`options:`

* `getLog` -- If true, also refresh the jobs log data (which may be large).  Default: `false`
* `getFailures` -- If true, also refresh the jobs failure results (which may be large).  Default: `false`

`callback(error, result)` -- Result is true if refresh was successful. When running as `Meteor.isServer` with fibers, the callback may be omitted and the return value is the result, so in this case this method is chainable.

```js
job.refresh(function (err, result) {
  if (result) {
    // Refreshed
  }
});
```

### job.done(result, [options], [callback]) - Anywhere
#### Change the state of a running job to `'completed'`.
#### Requires permission: Server, `admin`, `worker` or `jobDone`

`result` is any EJSON object.  If this job is configured to repeat, a new job will automatically be cloned to rerun in the future.  Result will be saved as an object. If passed result is not an object, it will be wrapped in one.

`options:` -- None currently.

`callback(error, result)` -- Result is true if completion was successful. When running as `Meteor.isServer` with fibers, the callback may be omitted and the return value is the result.

```js
job.done(function (err, result) {
  if (result) {
    // Status updated
  }
});

// Pass a non-object result
job.done("Done!");
// This will be saved as:
// { "value": "Done!" }
```

### job.fail(error, [options], [callback]) - Anywhere
#### Change the state of a running job to `'failed'`.
#### Requires permission: Server, `admin`, `worker` or `jobFail`

The job's next state depends on how the its `job.retry()` settings are configured. It will either become `'failed'` or go to `'waiting'` for the next retry. `error` is any EJSON object and will be saved as an object. If passed error is not an object, it will be wrapped in one.

`options:`

* `fatal` -- If true, no additional retries will be attempted and this job will go to a `'failed'` state. Default: `false`

`callback(error, result)` -- Result is true if failure was successful (heh). When running as `Meteor.isServer` with fibers, the callback may be omitted and the return value is the result.

```js
job.fail(
  {
    reason: 'This job has failed again!',
    code: 44
  }
  {
    fatal: false  // Default case
  },
  function (err, result) {
    if (result) {
      // Status updated
    }
  }
});

// Pass a non-object error
job.fail("Error!");
// This will be saved as:
// { "value": "Error!" }
```

### job.pause([options], [callback]) - Anywhere
#### Change the state of a job to `'paused'`.
#### Requires permission: Server, `admin`, `manager` or `jobPause`

Only `'ready'` and `'waiting'` jobs may be paused. This specifically does nothing to affect running jobs. To stop a running job, you must use `job.cancel()`.

`options:` -- None currently.

`callback(error, result)` -- Result is true if pausing was successful. When running as `Meteor.isServer` with fibers, the callback may be omitted and the return value is the result.

```js
job.pause(function (err, result) {
  if (result) {
    // Status updated
  }
});
```

### job.resume([options], [callback]) - Anywhere
#### Change the state of a job from `'paused'` to `'waiting'`
#### Requires permission: Server, `admin`, `manager` or `jobResume`

`options:` -- None currently.

`callback(error, result)` -- Result is true if resuming was successful. When running as `Meteor.isServer` with fibers, the callback may be omitted and the return value is the result.

```js
job.resume(function (err, result) {
  if (result) {
    // Status updated
  }
});
```

### job.cancel([options], [callback]) - Anywhere
#### Change the state of a job to `'cancelled'`.
#### Requires permission: Server, `admin`, `manager` or `jobCancel`

Any job that isn't `'completed'`, `'failed'` or already `'cancelled'` may be cancelled. Cancelled jobs retain any remaining retries and/or repeats if they are later restarted.

`options:`

* `antecedents` -- Also cancel all cancellable jobs that this job depends on.  Default: `false`
* `dependents` -- Also cancel all cancellable jobs that depend on this job.  Default: `true`

`callback(error, result)` -- Result is true if cancellation was successful. When running as `Meteor.isServer` with fibers, the callback may be omitted and the return value is the result.

```js
job.cancel(
  {
    antecedents: false,
    dependents: true    // Also cancel all jobs that will
                        // never run without this one.
  },
  function (err, result) {
    if (result) {
      // Status updated
    }
  }
);
```

### job.restart([options], [callback]) - Anywhere
#### Change the state of a `'failed'` or `'cancelled'` job to `'waiting'` to be retried.

A restarted job will retain any repeat count state it had when it failed or was cancelled.

`options:`

* `retries` -- Number of additional retries to attempt before failing with `job.retry()`. Default: `0`. These retries add to any remaining retries already on the job (such as if it was cancelled).
* `until` -- Keep retrying until this `Date`, or until the number of retries is exhausted, whichever comes first. Default: Prior value of `until`. Note that if you specify a value for `until` when restarting a repeating job, it will only apply to the first run of the job. Any repeated runs of the job will use the repeat `until` value for retries.
* `antecedents` -- Also restart all `'cancelled'` or `'failed'` jobs that this job depends on.  Default: `true`
* `dependents` -- Also restart all `'cancelled'` or `'failed'` jobs that depend on this job.  Default: `false`

`callback(error, result)` -- Result is true if restart was successful. When running as `Meteor.isServer` with fibers, the callback may be omitted and the return value is the result.

```js
job.restart(
  {
    antecedents: true,  // Also restart all jobs that must
                        // complete before this job can run.
    dependents: false,
    retries: 0          // Only try one more time. This is the default.
  },
  function (err, result) {
    if (result) {
      // Status updated
    }
  }
);
```

### job.rerun([options], [callback]) - Anywhere
#### Clone a completed job and run it again
#### Requires permission: Server, `admin`, `creator` or `jobRerun`

`options:`

* `repeats` -- Number of times to repeat the job, as with `job.repeat()`.
* `until` -- Keep repeating until this `Date`, or until the number of repeats is exhausted, whichever comes first. Default: prior value of `until`
* `wait` -- Time to wait between reruns. Default is the existing `job.repeat({ wait: ms })` setting for the job.

`callback(error, result)` -- Result is true if rerun was successful. When running as `Meteor.isServer` with fibers, the callback may be omitted and the return value is the result.

```js
job.rerun(
  {
    repeats: 0,   // Only repeat this once
                  // This is the default
    wait: 60000   // Wait a minute between repeats
                  // Default is previous setting
  },
  function (err, result) {
    if (result) {
      // Status updated
    }
  }
);
```

### job.remove([options], [callback]) - Anywhere
#### Permanently remove this job from the job collection
#### Requires permission: Server, `admin`, `manager` or `jobRemove`

The job must be `'completed'`, `'failed'`, or `'cancelled'` to be removed.

`options:` -- None currently.

`callback(error, result)` -- Result is true if removal was successful. When running as `Meteor.isServer` with fibers, the callback may be omitted and the return value is the result.

```js
job.remove(function (err, result) {
  if (result) {
    // Job removed from server.
  }
});
```

### job.type - Anywhere
#### Contains the type of a job

Always a string. Useful for when `getWork` or `processJobs` are configured to accept multiple job types. This may not be changed after a job is created.

### job.data - Anywhere
#### Contains the job data needed by the worker to complete a job of a given type

Always an object. This may not be changed after a job is created.

### job.doc - Anywhere
#### Contains the full job document for the job
Always an object, as stored in the underlying JobCollection. This may not be changed after a job is created.

## JobQueue API

JobQueue is similar in spirit to the [async.js](https://github.com/caolan/async) [queue](https://github.com/caolan/async#queue) and [cargo]([queue](https://github.com/caolan/async#cargo)) except that it gets its work from the job collection via calls to `jc.getWork()`

New jobQueues are created by calling the following job-collection method (documented above):
`q = jc.processJobs()`

All `JobQueue` methods may be run on the server or client

### q.pause() - Anywhere
#### Pause the JobQueue

This means that no more work will be requested from the job collection, and no new workers will be called with jobs that already exist in this local queue. Jobs that are already running locally will run to completion. Note that a JobQueue may be created in the paused state by running `q.pause()` immediately on the returned new jobQueue.

```js
q.pause()
```

### q.resume() - Anywhere
#### Undoes a `q.pause()`, returning the queue to the normal running state

```js
q.resume()
```

### q.trigger() - Anywhere
#### Externally trigger the JobQueue to seek new work

This method manually causes the same action that expiration of the `pollInterval` does internally within JobQueue. This is useful for creating responsive JobQueues that are triggered by a Meteor [observe](http://docs.meteor.com/#/full/observe) based mechanism, rather than time based polling.

```js
// Simple observe based queue
q = jc.processJobs(
  // Type of job to request
  // Can also be an array of job types
  'jobType',
  {
    pollInterval: 1000000000, // Don't poll
  },
  function (job, callback) {
    // Only called when there is a valid job
    job.done();
    callback();
  }
);

jc.find({ type: 'jobType', status: 'ready' })
  .observe({
     added: function () { q.trigger(); }
  })'
```

### q.shutdown([options], [callback]) - Anywhere
#### Shuts down the queue, with several possible levels of urgency

`options:`

* `level` -- May be 'hard' or 'soft'. Any other value will lead to a "normal" shutdown.
* `quiet` -- true or false. False by default, which leads to a "Shutting down..." message on `process.stderr`.

`callback()` -- Invoked once the requested shutdown conditions have been achieved.

Shutdown levels:

* `'soft'` -- Allow all local jobs in the queue to start and run to a finish, but do not request any more work. Normal program exit should be possible.
* `'normal'` -- Allow all running jobs to finish, but do not request any more work and fail any jobs that are in the local queue but haven't started to run. Normal program exit should be possible.
* `'hard'` -- Fail all local jobs, running or not. Return as soon as the server has been updated. Note: after a hard shutdown, there may still be outstanding work in the event loop. To exit immediately may require `process.exit()` depending on how often asynchronous workers invoke `'job.progress()'` and whether they die when it fails.

```js
q.shutdown({ quiet: true, level: 'soft' }, function () {
  // shutdown complete
});
```

### q.length() - Anywhere
#### Number of tasks ready to run

### q.full() - Anywhere
#### `true` if all of the concurrent workers are currently running

### q.running() - Anywhere
#### Number of concurrent workers currently running

### q.idle() - Anywhere
#### `true` if no work is currently running.

## Job document data models

The definitions below use a slight shorthand of the Meteor [Match pattern](http://docs.meteor.com/#matchpatterns) syntax to describe the valid structure of a job document. As a user of job-collection this is mostly for your information because jobs are automatically built and maintained by the package.

**Note:** If you would like to add private server-side data to a job document, you may add whatever you would like in a subdocument called `_private`. Such data will not be accepted via or returned from any of the jobCollection method calls.
**IMPORTANT CAVEAT!** If you use this feature, you *must* be careful to exclude `_private` from any query cursors returned from within a `publish` function, or you will leak this data to potentially untrusted clients.

```js
validId = (
  Match.test(v, Match.OneOf(String, Meteor.Collection.ObjectID))
);

validStatus = (
  Match.test(v, String) &&
  (v in ['waiting', 'paused', 'ready', 'running',
    'failed', 'cancelled', 'completed'])
);

validLogLevel = (
  Match.test(v, String) &&
  (v in ['info', 'success', 'warning', 'danger'])
);

validRetryBackoff = (
  Match.test(v, String) &&
  (v in ['constant', 'exponential'])
 );

validLog = [{
  time:    Date,
  runId:   Match.OneOf(
    Match.Where(validId),
    null
  ),
  level:   Match.Where(validLogLevel),
  message: String,
  data: Match.Optional(Object)
}];

validProgress = {
  completed: Match.Where(validNumGTEZero),
  total:     Match.Where(validNumGTEZero),
  percent:   Match.Where(validNumGTEZero)
};

validJobDoc = {
  _id:         Match.Optional(
    Match.OneOf(
      Match.Where(validId),
      null
    )
  ),
  runId:        Match.OneOf(
    Match.Where(validId),
    null
  ),
  type:         String,
  status:       Match.Where(validStatus),
  data:         Object,
  result:       Match.Optional(Object),
  failures:     Match.Optional([ Object ]),
  priority:     Match.Integer,
  depends:      [ Match.Where(validId) ],
  resolved:     [ Match.Where(validId) ],
  after:        Date,
  updated:      Date,
  log:          Match.Optional(validLog()),
  progress:     validProgress(),
  retries:      Match.Where(validIntGTEZero),
  retried:      Match.Where(validIntGTEZero),
  retryUntil:   Date,
  retryWait:    Match.Where(validIntGTEZero),
  retryBackoff: Match.Where(validRetryBackoff),
  repeats:      Match.Where(validIntGTEZero),
  repeated:     Match.Where(validIntGTEZero),
  repeatUntil:  Date,
  repeatWait:   Match.Where(validIntGTEZero),
  created:      Date
};
```

## DDP Method reference

These are the underlying Meteor methods that are actually invoked when a method like `.save()` or `.getWork()` is called. In most cases you will not need to program to this interface because the `JobCollection` and `Job` APIs do this work for you. One exception to this general rule is if you need finer control over allow/deny rules than is provided by the predefined `admin`, `manager`, `creator`, and `worker` access categories.

Each job-collection you create on a server causes a number of Meteor methods to be defined. The method names are prefaced with the name of the job collection (e.g. "myJobs_getWork") so that multiple job-collections on a server will not interfere with one another. Below you will find the Method API reference.

### `startJobServer(options)`
#### Start running the job collection server

* `options` -- No options currently used

    `Match.Optional({})`

Returns: `Boolean` - Success or failure

### `shutdownJobServer(options)`
#### Shut down the job collection server

* `options` -- Supports the following options:

    * `timeout` -- Time in ms until all outstanding jobs will be marked as failed.

    `Match.Optional({
      timeout: Match.Optional(Match.Where(validIntGTEOne))
    })`

Returns: `Boolean` - Success or failure

### `getJob(ids, options)`
#### Returns a Job document corresponding to provided id

* `ids` -- an Id or array of Ids to get from server

    `ids: Match.OneOf(Match.Where(validId), [ Match.Where(validId) ])`

* `options` -- Supports the following options:

    * `getLog` -- If true include the job log data in the returned job data. Default is false.

    `Match.Optional({
      getLog: Match.Optional(Boolean)
    })`

Returns: `validJobDoc()` or `[ validJobDoc() ]` depending on if `ids` is a single value or an array.

### `getWork(type, options)`
#### Returns jobs ready-to-run to a requesting worker

* `type` -- a string job type or an array of such types

    `type: Match.OneOf(String, [ String ])`

* `options` -- Supports the following options:

    * `maxJobs` -- The maximum number of jobs to return, Default: `1`

    `Match.Optional({
         maxJobs: Match.Optional(Match.Where(validIntGTEOne))
    })`

Returns: `validJobDoc()` or `[ validJobDoc() ]` depending on if maxJobs > 1.


### `jobRemove(ids, options)`
#### Permanently remove jobs from the job collection

* `ids` -- an Id or array of Ids to remove from server

    `ids: Match.OneOf(Match.Where(validId), [ Match.Where(validId) ])`

* `options` -- No options currently used

    `Match.Optional({})`

Returns: `Boolean` - Success or failure

### `jobPause(ids, options)`
#### Pauses a job in the job collection, changes status to `paused` which prevents it from running

* `ids` -- an Id or array of Ids to remove from server

    `ids: Match.OneOf(Match.Where(validId), [ Match.Where(validId) ])`

* `options` -- No options currently used

    `Match.Optional({})`

Returns: `Boolean` - Success or failure

### `jobResume(ids, options)`
#### Resumes (unpauses) a job in the job collection, returns it to the `waiting` state

* `ids` -- an Id or array of Ids to remove from server

    `ids: Match.OneOf(Match.Where(validId), [ Match.Where(validId) ])`

* `options` -- No options currently used

    `Match.Optional({})`

Returns: `Boolean` - Success or failure

### `jobCancel(ids, options)`
#### Cancels a job in the job collection. Cancelled jobs will not run and will stop running if already running.

* `ids` -- an Id or array of Ids to remove from server

    `ids: Match.OneOf(Match.Where(validId), [ Match.Where(validId) ])`

* `options` -- Supports the following options:
    * `antecedents` -- If true, all jobs that this one depends upon will also be cancelled. Default: `false`
    * `dependents` -- If true, all jobs that depend on this one will also be be cancelled. Default: `true`

    `Match.Optional({
        antecedents: Match.Optional(Boolean),
        dependents: Match.Optional(Boolean)
    })`

Returns: `Boolean` - Success or failure

### `jobRestart(ids, options)`
#### Restarts a cancelled or failed job.

* `ids` -- an Id or array of Ids to remove from server

    `ids: Match.OneOf(Match.Where(validId), [ Match.Where(validId) ])`

* `options` -- Supports the following options:
    * `retries` -- Number of additional times to retry running this job. Default: 1
    * `until` -- Retry until this time, or until the retries count is exhausted, whicever comes first. Default: prior value.
    * `antecedents` -- If true, all jobs that this one depends upon will also be restarted. Default: `true`
    * `dependents` -- If true, all jobs that depend on this one will also be be restarted. Default: `false`

    `Match.Optional({
        retries: Match.Optional(Match.Where validIntGTEOne),
        until: Match.Optional(Date),
        antecedents: Match.Optional(Boolean),
        dependents: Match.Optional(Boolean)
    })`

Returns: `Boolean` - Success or failure

### `jobSave(doc, options)`
#### Adds a job to the job collection in the `waiting` or `paused` state

* `doc` -- Job document of job to save to the server job-collection

    `validJobDoc()`

* `options` -- Supports the following options:
    * `cancelRepeats` --  If true and this job is an infinitely repeating job, will cancel any existing jobs of the same job type. Default is false.

    `Match.Optional({
      cancelRepeats: Match.Optional(Boolean)
    })`

Returns: `Match.Where(validId)` of the added job.

### `jobRerun(id, options)`
#### Creates and saves a new job based on an existing job that has successfully completed.

* `id` -- The id of the job to rerun

    `Match.Where(validId)`

* `options` -- Supports the following options:

    * `wait` -- Amount of time to wait until the new job runs in ms. Default: 0
    * `repeats` -- Number of times to repeat the new job. Default: 0
    * `until` -- Repeat until this time, or until the repeats count is exhausted, whicever comes first. Default: prior value.

    `Match.Optional({
      repeats: Match.Optional(Match.Where validIntGTEZero),
      until: Match.Optional(Date),
      wait: Match.Optional(Match.Where validIntGTEZero)
    })`

Returns: `Match.Where(validId)` of the added job.

### `jobProgress(id, runId, completed, total, options)`
#### Update the progress of a running job

* `id` -- The id of the job to update

    `Match.Where(validId)`

* `runId` -- The runId of this worker

    `Match.Where(validId)`

* `completed` -- The estimated amount of effort completed

    `Match.Where(validNumGTEZero)`

* `total` -- The estimated total effort

    `Match.Where(validNumGTZero)`

* `options` -- No options currently used

    `Match.Optional({})`

Returns: `Boolean` - Success or failure or `null` if job-collection is shutting down

### `jobLog(id, runId, message, options)`
#### Add an entry in the job log of a running job

* `id` -- The id of the job to update

    `Match.Where(validId)`

* `runId` -- The runId of this worker

    `Match.Where(validId)`

* `message` -- The text of the message to add to the log

    `String`

* `options` -- Supports the following options:

    * `level` -- The information level of this log entry. Must be a valid log level. Default: `'info'`
    * `data` -- An arbitrary object to store in the log entry

    `Match.Optional({
       level: Match.Optional(Match.Where(validLogLevel))
       data: Match.Optional Object
    })`

Returns: `Boolean` - Success or failure

### `jobDone(id, runId, result, options)`
#### Change a job's status to `completed`

* `id` -- The id of the job to update

    `Match.Where(validId)`

* `runId` -- The runId of this worker

    `Match.Where(validId)`

* `result` -- A result object to store with the completed job.

    `Object`

* `options` -- No options currently used

    `Match.Optional({})`

Returns: `Boolean` - Success or failure

### `jobFail(id, runId, err, options)`
#### Change a job's status to `failed`

* `id` -- The id of the job to update

    `Match.Where(validId)`

* `runId` -- The runId of this worker

    `Match.Where(validId)`

* `err` -- An error object to store with the failed job.

    `Object`

* `options` -- Supports the following options:
    * `fatal` -- If true, cancels any remaining repeat runs this job was scheduled to have. Default: false.

    `options: Match.Optional({
      fatal: Match.Optional(Boolean)
    })`

Returns: `Boolean` - Success or failure
