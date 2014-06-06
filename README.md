#jobCollection

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

   myJobs = jobCollection('myJobQueue', {
      // Set remote access permissions
      // much finer grained control is possible!
      permissions: {
         allow: function (userId, method) {
            // Allow Client/Remote access for all methods...
            if userId
               return true  // ...to any authenticated user!
            return false
         }
      }
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

**TBD**

### jc.promote([milliseconds])
#### Sets time between checking for delayed jobs that are ready - Server only

Default: 15000, (15 seconds)

### jc.makeJob(jobDoc)
#### Make a Job object from a jobCollection document - Server or Client

```js
doc = jc.findOne({});
if (doc) {
   job = jc.makeJob('jobQueue', doc);
}
```



## Advanced topics

### Job document data models

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