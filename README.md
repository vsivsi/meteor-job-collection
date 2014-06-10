# jobCollection

**NOTE:** This Package remains experimental until v0.1.0 is released, and while the API methods described here are maturing, they may still change.

##Intro

`jobCollection` is a powerful and easy to use job manager designed and built for Meteor.js

It solves the following problems (and more):

*    Schedule jobs to run (and repeat) in the future, persisting across server restarts
*    Move work out of the Meteor's single threaded event-loop
*    Permit work on computationally expensive jobs to run anywhere
*    Track jobs and their progress, and automatically retry failed jobs
*    Easily build an admin UI to manage all of the above using Meteor's reactivity and UI goodness

### Quick example

The code snippets below show a Meteor server that creates a `jobCollection`, Meteor client code that subscribes to it and creates a new job, and a pure node.js program that can run *anywhere* and work on such jobs.

```js
///////////////////
// Server
if (Meteor.isServer) {

   myJobs = jobCollection('myJobQueue');
   myJobs.allow({
    // Grant full permission to any authenticated user
    admin: function (userId, method, params) { return (userId ? true : false); }
   });

   Meteor.startup(function () {
      // Normal Meteor publish call, the server always
      // controls what each client can see
      Meteor.publish('allJobs', function () {
         myJobs.find({});
      });

      // Start the myJobs queue running
      myJobs.startJobs();
   }
}
```

Alright, the server is set-up and running, now let's add some client code to create/manage a job.

```js
///////////////////
// Client
if (Meteor.isClient) {

   myJobs = jobCollection('myJobQueue');
   Meteor.subscribe('allJobs');

   // Because of the server settings, the code below will only work
   // if the client is authenticated.
   // On the server all of it would run unconditionally

   // Create a job:
   job = myJobs.createJob('sendEmail', // type of job
      // Job data, defined by you for type of job
      // whatever info is needed to complete it.
      // May contain links to files, etc...
      {
         address: 'bozo@clowns.com',
         subject: 'Critical rainbow hair shortage'
         message: 'LOL; JK, KThxBye.'
      }
   );

   // Set some proerties of the job and then submit it
   job.priority('normal')
      .retry({ retries: 5,
               wait: 15*60*1000 })  // 15 minutes between attempts
      .delay(60*60*1000)            // Wait an hour before first try
      .save();                      // Commit it to the server

   // Now that it's saved, this job will appear as a document
   // in the myJobs Collection, and will reactively update as
   // its status changes, etc.

   // Any job document from myJobs can be turned into a Job object
   job = myJobs.makeJob(myJobs.findOne({}));

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
}
```

**Q:** Okay, that's cool, but where does the actual work get done?

**A:** Anywhere you want!

Below is a pure node.js program that can obtain jobs from the server above and "get 'em done."
Powerfully, this can be run ***anywhere*** that has node.js and can connect to the server.

```js
///////////////////
// node.js Worker
var DDP = require('ddp');
var DDPlogin = require('ddp-login');
var Job = require('meteor-job')

// Job here has essentially the same API as jobCollection on Meteor
// In fact, Meteor jobCollection is built on top of the 'node-job' npm package!

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
      // This will keep running indefinitely, obtaining new work from the
      // server whenever it is available.
      workers = Job.processJobs('myJobQueue', 'sendEmail', function (job, cb) {
         // This will only be called if a 'sendEmail' job is obtained
         email = job.data.email // Only one email per job
         sendEmail(email.address, email.subject, email.message, function(err) {
            if (err) {
               job.log("Sending failed with error" + err, {level: 'warning'});
               job.fail("" + err);
            } else {
               job.done();
            }
            cb(); // Be sure to invoke the callback when work on this job has finished
         });
      });
   });
});
```

Worker code very similar to the above (without all of the DDP setup) can run on the Meteor server or even a Meteor client.

### Design

The design of jobCollection is heavily influenced by [Kue](https://github.com/LearnBoost/kue) and to a lesser extent by the [Maui Cluster Scheduler](https://en.wikipedia.org/wiki/Maui_Cluster_Scheduler). However, unlike Kue's use of Redis Pub/Sub and an HTTP API, `jobCollection` uses MongoDB, Meteor, and Meteor's DDP protocol to provide persistence, reactivity, and secure remote access.

As the name implies, a `jobCollection` looks and acts like a Meteor Collection because under the hood it actually is one. However, other than `.find()` and `.findOne()`, all accesses to a `jobCollection` happen via the easy to use API on `Job` objects. Most `Job` API calls are transformed internally to Meteor [Method](http://docs.meteor.com/#methods_header) calls. This is cool because the underlying `Job` class is implemented as pure Javascript that can run in both the Meteor server and client environments, and most significantly as pure node.js code running independently from Meteor (as shown in the example code above).

## Installation

I've only tested with Meteor v0.8. It may run on Meteor v0.7 as well, I don't know.

Requires [meteorite](https://atmospherejs.com/docs/installing). To add to your project, run:

    mrt add jobCollection

The package exposes a global object `jobCollection` on both client and server.


**NOTE!** Sample app and tests mentioned below are not implemented yet!

If you'd like to try out the sample app, you can clone the repo from github:

```
git clone --recursive \
    https://github.com/vsivsi/meteor-job-collection.git \
    jobCollection
```

Then go to the `sampleApp` subdirectory and run meteorite to launch:

```
cd fileCollection/sampleApp/
mrt
```

You should now be able to point your browser to `http://localhost:3000/` and play with the sample app.

To run tests (using Meteor tiny-test) run from within the `jobCollection` subdirectory:

    meteor test-packages ./

Load `http://localhost:3000/` and the tests should run in your browser and on the server.

## Use

### Security

## API

### jc = new jobCollection([name], [options])
#### Creates a new jobCollection. - Server and Client

Creating a new `jobCollection` is similar to creating a new Meteor Collection. You simply specify a name (which defaults to `"queue"`. There currently are no valid `options`, but the parameter is included for possible future use. On the server there are some additional methods you will probably want to invoke on the returned object to configure it further.

For security and simplicity the traditional client allow/deny rules for Meteor collections are preset to deny all direct client `insert`, `update` and `remove` type operations on a `jobCollection`. This effectively channels all remote activity through the `jobCollection` DDP methods, which may be secured using allow/deny rules specific to `jobCollection`. See the documentation for `js.allow()` and `js.deny()` for more information.

```js
// the "new" is optional
jc = jobCollection('defaultJobCollection');
```

### jc.setLogStream(writeStream)
#### Sets where the jobCollection method invocation log will be written - Server only

You can log everything that happens to a jobCollection on the server by providing any valid writable stream. You may only call this once, unless you first call `jc.shutdown()`, which will automatically close the existing `logStream`.

```js
// Log everything to stdout
jc.setLogStream(process.stdout);
```

### jc.logConsole
#### Member variable that turns on DDP method call logging to the console - Client only

```js
jc.logConsole = false  # Default. Do not log method calls to the client console
```

### jc.promote([milliseconds])
#### Sets time between checks for delayed jobs that are now ready to run - Server only

`jc.promote()` may be called at any time to change the polling rate. jobCollection must poll for this operation because it is time that is changing, not the contents of the database, so there are no database updates to listen for.

```js
jc.promote(15*1000);  // Default: 15 seconds
```

### jc.allow(options)
#### Allow remote execution of specific jobCollection methods - Server only

Compared to vanilla Meteor collections, `jobCollection` has very a different set of remote methods with specific security implications. Where the `.allow()` method on a Meteor collection takes functions to grant permission for `insert`, `update` and `remove`, `jobCollection` has more functionality to secure and configure.

By default no remote operations are allowed, and in this configuration, jobCollection exists only as a server-side service, with the creation, management and execution of all jobs dependent on the server.

The opposite extreme is to allow any remote client to perform any action. Obviously this is totally insecure, but is perhaps valuable for early development stages on a local firewalled network.

```js
// Allow any remote client (Meteor client or node.js application) to perform any action
jc.allow({
  // The "admin" below represents the grouping of all remote methods
  admin: function (userId, method, params) { return true; };
});
```

If this seems a little reckless (and it should), then here is how you can grant admin rights specifically to an single authenticated Meteor userId:

```js
// Allow any remote client (Meteor client or node.js application) to perform any action
jc.allow({
  // Assume "adminUserId" contains the Meteor userId string of an admin super-user.
  // The array below is assumed to be an array of userIds
  admin: [ adminUserId ]
});

// The array notation in the above code is a shortcut for:
var adminUsers = [ adminUserId ];
jc.allow({
  // Assume "adminUserId" contains the Meteor userId string of an admin super-user.
  admin: function (userId, method, params) { return (userId in adminUsers); };
});
```

In addition to the all-encompassing `admin` method group, there are three others:

*    `manager` -- Managers can remotely manage the jobCollection (e.g. cancelling jobs).
*    `creator` -- Creators can remotely make new jobs to run.
*    `worker` -- Workers can get Jobs to work on and can update their status as work proceeds.

All remote methods affecting the jobCollection fall into at least one of the four groups, and for each client-capable API method below, the group(s) it belongs to will be noted.

In addition to the above groups, it is possible to write allow/deny rules specific to each `jobCollection` DDP method. This is a more advanced feature and the intent is that the four permission groups described above should be adequate for many applications. The DDP methods are generally lower-level than the methods available on `Job` and they do not necessarily have a one-to-one relationship. Here's an example of how to given permission to create new "email" jobs to a single userId:

```js
// Assumes emailCreator contains a Meteor userId
jc.allow({
  jobSave: function (userId, method, params) {
              if ((userId === emailCreator) &&
                  (params[0].type === 'email')) { # params[0] is the new job doc
                  return true;
              }
              return false;
           };
});
```

### jc.deny(options)
#### Override allow rules - Server only

This call has the same semantic relationship with `allow()` as it does in Meteor collections. If any deny rule is true, then permission for a remote method call will be denied, regardless of the status of any other allow/deny rules. This is powerful and far reaching. For example, the following code will turn off all remote access to a jobCollection (regardless of any other rules that may be in force):

```js
jc.deny({
  // The "admin" below represents the grouping of all remote methods
  admin: function (userId, method, params) { return false; };
});
```

See the `allow` method above for more details.

### jc.makeJob(jobDoc)
#### Make a Job object from a jobCollection document - Server or Client

```js
doc = jc.findOne({});
if (doc) {
   job = jc.makeJob('jobQueue', doc);
}
```



## DDP Method reference

```
startJobs(options)
options : Match.Optional({})
returns Boolean

stopJobs(options)
options: Match.Optional({
  timeout: Match.Optional(Match.Where(validIntGTEOne))
  })
returns Boolean

getJob(ids, options)
    ids: Match.OneOf(Meteor.Collection.ObjectID, [ Meteor.Collection.ObjectID ])
    check options, Match.Optional({
      getLog: Match.Optional(Boolean)
    })
    options.getLog ?= false
    if single
      return d[0]
    else
      return d
    return null

getWork(type, options)
  type: Match.OneOf(String, [ String ])
  options: Match.Optional({
      maxJobs: Match.Optional(Match.Where(validIntGTEOne))
  })
  options ?= {}
  return [ validJobDoc() ]

jobRemove(ids, options)
    ids: Match.OneOf(Meteor.Collection.ObjectID, [ Meteor.Collection.ObjectID ])
    check options, Match.Optional {}
    returns Boolean

jobResume(ids, options)
    ids: Match.OneOf(Meteor.Collection.ObjectID, [ Meteor.Collection.ObjectID ])
    options: Match.Optional({})
    returns Boolean

jobCancel(ids, options)
    ids: Match.OneOf(Meteor.Collection.ObjectID, [ Meteor.Collection.ObjectID ])
    options: Match.Optional({
      antecedents: Match.Optional(Boolean)
      dependents: Match.Optional(Boolean)
    })
    options ?= {}
    options.antecedents ?= true
    options.dependents ?= false
    returns Boolean

jobRestart(ids, options)
    ids: Match.OneOf(Meteor.Collection.ObjectID, [ Meteor.Collection.ObjectID ])
    options: Match.Optional({
      retries: Match.Optional(Match.Where(validIntGTEOne))
      antecedents: Match.Optional(Boolean)
      dependents: Match.Optional(Boolean)
    })
    options ?= {}
    options.retries ?= 1
    options.retries = Job.forever if options.retries > Job.forever
    options.dependents ?= false
    options.antecedents ?= true
    returns Boolean

jobSave(doc, options)
    doc: validJobDoc()
    options: Match.Optional({
      cancelRepeats: Match.Optional(Boolean)
    })
    check doc.status, Match.Where (v) ->
      Match.test(v, String) and v in [ 'waiting', 'paused' ]
    options ?= {}
    options.cancelRepeats ?= true
    returns Meteor.Collection.ObjectID

jobProgress(id, runId, completed, total, options)
    id: Meteor.Collection.ObjectID
    runId: Meteor.Collection.ObjectID
    completed: Match.Where(validNumGTEZero)
    total: Match.Where(validNumGTZero)
    options: Match.Optional({})
    options ?= {}
    return Boolean or null

jobLog(id, runId, message, options)
    id: Meteor.Collection.ObjectID
    runId: Meteor.Collection.ObjectID
    message: String
    options: Match.Optional({
      level: Match.Optional(Match.Where(validLogLevel))
    })
    options ?= {}
    returns Boolean

jobRerun(id, options)
    id: Meteor.Collection.ObjectID
    options: Match.Optional({
      repeats: Match.Optional(Match.Where(validIntGTEZero))
      wait: Match.Optional(Match.Where(validIntGTEZero))
    })
    options ?= {}
    options.repeats ?= 0
    options.repeats = Job.forever if options.repeats > Job.forever
    options.wait ?= 0
    returns Boolean

jobDone(id, runId, result, options)
    id, Meteor.Collection.ObjectID
    runId, Meteor.Collection.ObjectID
    result, Object
    options, Match.Optional({})
    options ?= {}
    returns Boolean

jobFail(id, runId, err, options)
    id: Meteor.Collection.ObjectID
    runId: Meteor.Collection.ObjectID
    err: String
    options: Match.Optional({
      fatal: Match.Optional(Boolean)
    })
    options ?= {}
    options.fatal ?= false
    returns Boolean
```

## Job document data models

The definitions below use a slight shorthand of the Meteor [Match pattern](http://docs.meteor.com/#matchpatterns) syntax to describe the valid structure of a job document. As a user of `jobCollection` this is mostly for your information because jobs are automatically built and maintained by the package.

```js
validStatus = (
   Match.test(v, String) &&
   (v in [
      'waiting',
      'paused',
      'ready',
      'running',
      'failed',
      'cancelled',
      'completed'
   ])
);

validLogLevel = (
   Match.test(v, String) &&
   (v in [
      'info',
      'success',
      'warning',
      'danger'
   ])
);

validLog = [{
      time:    Date,
      runId:   Match.OneOf(
                  Meteor.Collection.ObjectID, null
               ),
      level:   Match.Where(validLogLevel),
      message: String
}];

validProgress = {
  completed: Match.Where(validNumGTEZero),
  total:     Match.Where(validNumGTEZero),
  percent:   Match.Where(validNumGTEZero)
};

validJobDoc = {
   _id:       Match.Optional(
                 Match.OneOf(
                    Meteor.Collection.ObjectID,
                    null
              )),
  runId:      Match.OneOf(
                 Meteor.Collection.ObjectID,
                 null
              ),
  type:       String,
  status:     Match.Where(validStatus),
  data:       Object
  result:     Match.Optional(Object),
  priority:   Match.Integer,
  depends:    [ Meteor.Collection.ObjectID ],
  resolved:   [ Meteor.Collection.ObjectID ],
  after:      Date,
  updated:    Date,
  log:        Match.Optional(validLog()),
  progress:   validProgress(),
  retries:    Match.Where(validNumGTEZero),
  retried:    Match.Where(validNumGTEZero),
  retryWait:  Match.Where(validNumGTEZero),
  repeats:    Match.Where(validNumGTEZero),
  repeated:   Match.Where(validNumGTEZero),
  repeatWait: Match.Where(validNumGTEZero)
};
```