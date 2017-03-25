## Revision history

#### V.NEXT

* Added `errorCallback` option to `processJobs()`. This gives workers a way to log network and other errors and do something other than write them to `console.error` (the default and previous behavior).
* Added workaround for bug/feature in later.js that caused the first run of periodic jobs to sometimes occur immediately after scheduling. Thanks @mitar.
* Removed section recommending capped collections for managing removal of old finished jobs. This no longer works as of MongoDB 3.2. Thanks @mcoenca.
* Documentation improvements
* Updated package dependencies

### 1.4.0

* Added support for new "callbackStrict" option to `processJobs()`. When `true` (default `false`) `processJobs()` will throw an error if a worker function calls its callback more than once. Previously it only wrote a message to stderr in all cases. That functionality is preserved with this change.
* Added `job.repeatRetries` as an optional (for backward compatibility) attribute of the job document model. This attribute is used (when present) for the number of retries to attempt for the new instance of a repeating job. When missing (such as will be the case for jobs created by older versions of meteor-job) the old method of using `job.retries + job.retried` is used.
* Fix an error caused by a check on `retries` when a waiting/ready job is cancelled, restarted and then refreshed. This condition also occurs when `job.restart()` is called with option `retries` greater than the current value of `job.retried` (which is the default case after a cancel of a non-running job.) Thanks @huttarichard.
* In coordination with the above change, the `retries` option of `job.restart()` will now accept a value of zero.
* Fixed race condition in `processJobs()` that could cause `Job.getWork()` to run after the queue is paused or stopped, leading to a zombie job on the server.
* Documentation improvements
* Updated package dependencies

### 1.3.3

* Fixed error affecting all of the *Jobs functions which caused them to only process the first 256 jobs in the provided list of _id values.
* Updated package dependencies

### 1.3.2

* Fix broken links in README

### 1.3.1

* Updated package dependencies
* Documentation improvements (typos)

### 1.3.0

* Added `delayDeps` option to `job.done()` to allow dependent jobs to be delayed after the completion of an antecedent job. Thanks to @a4xrbj1 for suggesting.
* Fixed bug in `Job.jobStatuses`, Thanks @niceilm
* Invoking server-only or client-only methods in the wrong environment now generates a warning method. Thanks @aardvarkk.
* Additional indexes added to make built-in queries more efficient for large collections. Thanks @mitar.
* Internal improvements in event handlers. Thanks @mitar.
* Documentation improvements, Thanks @rhyslbw, @mitar and @jdcc !
* Updated job subproject to v1.3.2

### 1.2.3

* Fix issue when very long `promote()` cycles are used, causing waiting jobs that are ready to run at a server restart to be delayed one full promotion cycle. Thanks to @KrishnaPG for reporting this.

### 1.2.2

* Fixed bug in the `jc.getWork()` `workTimeout` functionality that could cause a running job to immediately auto-expire on the server if it was previously run with a `workTimeout` value, and was then subsequently run without a `workTimeout` value after the original job was rerun, restarted, retried or repeated.
* Updated job subproject to v1.3.1
* Updated README to include links to job-collection playground app and node.js worker repos

### 1.2.1

* Fixed `log()` on jobs without `runId` by loosening check in `jobLog()`. Thanks @sprohaska for the PR!

### 1.2.0

* Added ability for workers to specify a timeout for running jobs, so that if they crash or lose connectivity the job can automatically fail and be restarted. `getWork()` and `processJobs()` now each have a new option `workTimeout` that sets the number of milliseconds until a job can be automatically failed on the server. If not specified, the default behavior is as before (running jobs with no active worker need to be handled by the developer.) Thanks to @aldeed for the idea of making this a worker setting.
* Added `repeatId` option to `job.done()` which when `true` will cause the successful return value of a repeating job to be the `_id` of the newly scheduled job. Thanks to @tcastelli for this idea.
* Added `jc.events`, which is a node.js Event Emitter allowing server code to register callbacks to log or generate statistics based upon all job-collection DDP methods. There are two main events currently implemented: `'call'` for successful DDP method calls, and `'error'` for any errors thrown in such calls. There are also events defined for each of the 18 DDP methods (e.g. `jobDone` or `getWork`). These events emit for every such call, whether successful for not.
* Added new DDP method methods `job.ready()` and `jc.readyJobs()` to provide a standard way to promote jobs from `'waiting'` to `'ready'`.
* Throw an error when a buggy monkey patch has been applied to `Mongo.collection` (usually by some other package). See [this discussion](https://github.com/vsivsi/meteor-file-sample-app/issues/2#issuecomment-120780592) for details.
* The built-in default server logging mechanism (through `setLogStream()`) has been refactored to be built on top of the new Event Emitter mechanism. It otherwise works exactly as before.
* Providing a falsy value of option `pollInterval` when calling `Job.processJobs()` will now disable polling in favor of using `q.trigger` exclusively.
* Fixed bug where `q.trigger()` caused a `getWork()` call, even when the queue is paused.
* Fixed a bug in `job.rerun()` that caused it to fail if called with a later.js object for the wait parameter.
* Documentation updates and other improvements, with thanks to @skosch for a documentation PR.

### 1.1.4

* Fixed issue when using multiple job-collections with different DDP connections in use. Thanks to @mart-jansink for reporting [this issue](https://github.com/vsivsi/meteor-job-collection/issues/84).

### 1.1.3

* Documentation improvements. Thanks @kahmali!
* Added explicit package version to `onTest()` call to work around a Meteor issue when running `meteor test-packages` within an app.
* Fixes issue when `getJob()` called with `getLog` or `getFailures` options.
* Fixes incorrect log level of `'warn'` for job cancellation (correct is `'warning'`).
* Thanks to @kingkevin for PR fixing the above two issues.
* Added a client polyfill for Function.bind() which is missing from phantomJS

### 1.1.2

* Fixed a bug that caused server-side calls to job collection using callbacks to throw rather than properly propagating errors via the provided callback.

### 1.1.1

* Updated meteor-job package to 1.1.1, fixing a bug that could cause JobQueues to get more work than configured when using `q.trigger()` or very short pollIntervals.

### 1.1.0

* Support for using later.js schedules to configure repeating jobs.
* Removed unnecessary server-side console output.

### 1.0.0

* `jc.startJobs` and `jc.stopJobs` have been renamed to `jc.startJobServer` and `jc.shutdownJobServer` respectively. The old versions will now generate deprecation warnings.
* `jc.makeJob()` and `jc.createJob()` have been deprecated in favor of just calling `new Job(...)`
* Fixed an issue similar to #51 on the client-side.
* Fixed issue #55. All standard Mongo.Collection options should now work with JobCollections as well.
* Updated versions of package dependencies
* Fixed issue #41. The potential race condition in getWork is handled internally
* Fixed issue #57. Default MongoDB indexes enabled by default
* Fixed issue #55, all valid Mongo.Collection options are now supported. However, transformed documents may fail to validate unless "scrubbed". More work needs to go into documenting this.
* Fixed #28. Eliminated all "success" console logs.
* job objects now have `job.doc` readable attribute
* `jc.jobDocPattern` can now be used to validate Job documents.
* `j.refresh()` is now chainable
* Added `jq.trigger()` method to provide a mechanism to trigger `getWork` using an alternative method to `pollInterval`
* `job.log()` can now accept a `data` option, which must be an object.
* `log.data` field is now permitted in the Job document model.
* When `job.fail(err)` is used, the error object stored in the `failures` array will have the `runId` as an added field.
* `connection` option to `new JobCollection()` on client or server will now direct the local Job Collection to connect to an alternate remote server's Job Collection rather than using the default connection (client) or hosting a collection locally (server).

### 0.0.18

* Fixed issue #51, which caused errors on the server-side when multiple job-collection instances were used.

### 0.0.17

#### Note! There are some breaking changes here!  Specifically, the `job.fail()` change below. See the docs for specifics.

* Added support for Meteor 0.9.x style packages, including name change to accomodate
* `job.fail()` now takes an object for `error`. Previously this was a string message.
* Refactored JobCollection classes
* Jobs that are ready-to-run go straight from `waiting` to `ready` without waiting for a promote cycle to come around.
* Don't check for `after` and `retries` in `getWork()`

#### The following two features are experimental and may change significantly or be eliminated.

* Allow the server to add data to `job._private` that won't be shared with a client via `getWork()` and `getJob()`. Be sure not to publish cursors that return `job._private`!
* Added support for `@scrub` hook function to sanitize documents before validating them in `getWork()` and `getJob()`

### 0.0.16

* Updated to use the latest version of the `meteor-job` npm package

### 0.0.15

* Added `until` option for `job.repeat()`, `job.retry()`, job.restart() and job.rerun().
* Added `jc.foreverDate` to indicate a Date that will never come
* Fixed bug where `jc.forever` was not available
* Default Date for `job.after()` is now based on the server clock, not the clock of the machine creating the job. (thanks @daeq)
* Added `created` field to job document model to keep track of when a job was first created on the server

### 0.0.14

* Added `idGeneration` and `noCollectionSuffix` options to JobCollection constructor. Thanks to @mitar for suggestions.
* Removed unnecessary console log outputs
* Updated README to point to new sample app, and to clarify the use of `jc.promote()` in Meteor multi-instance deployments.

### 0.0.13

* Fixed bugs in client simulations of stopJobs and startJobs DDP methods

### 0.0.12

* Fixed bug due to removal of validNumGTEOne

### 0.0.11

* Fixed bug in jobProgress due to missing validNumGTZero

### 0.0.10

* Changed the default value of `job.save()` `cancelRepeats` option to be `false`.
* Fixed a case where the `echo` options to `job.log()` could be sent to the server, resulting in failure of the operation.
* Documentation improvements courtesy of @dandv.

### 0.0.9

* Added `backoff` option to `job.retry()`. Implements resolves enhancement request [#2](https://github.com/vsivsi/meteor-job-collection/issues/2)

### 0.0.8

* Fixed bug introduced by "integer enforcement" change in v0.0.7. Integers may now be up to 53-bits (the Javascript maxInt). Fixes [#3](https://github.com/vsivsi/meteor-job-collection/issues/3)
* Fixed sort inversion of priority levels in `getWork()`. Fixes [#4](https://github.com/vsivsi/meteor-job-collection/issues/4)
* Thanks to @chhib for reporting the above two issues.

### 0.0.7

* Bumped meteor-job version to 0.0.9, fixing several bugs in Meteor.server and Meteor.client workers handling.
* Corrected validation of jobDocuments for non-negative integer attributes (integer enforcement was missing).
* jc.promote() formerly had a minimum valid polling rate of 1000ms, now any value > 0ms is valid
* Added a few more acceptance tests including client and server scheduling and running of a job.
* Documentation improvements

### 0.0.6

* Added initial testing harness
* Fixed issue with collection root name in DDP method naming.
* Changed evaluation of allow/deny rules so deny rules run first, just like in Meteor.
* Documentation improvements.

### 0.0.5

* Really fixed issue #1, thanks again to @chhib for reporting this.

### 0.0.4

* Test release debugging git submodule issues around issue #1

### 0.0.3

* Fixed issue #1, thanks to @chhib for reporting this.

### 0.0.2

* Documentation improvements
* Removed meteor-job subproject and added npm dependency on it instead

### 0.0.1

* Initial revision.
