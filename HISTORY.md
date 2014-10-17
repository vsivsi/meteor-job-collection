## Revision history

### v.NEXT

* `job.fail()` now takes an object for `error`. Previously this was a string message.
* Jobs that are ready-to-run go straight from `waiting` to `ready` without waiting for a promote cycle to come around.
* Don't check for `after` and `retries` in `getWork()`
* Allow the server to add data to `job._private` that won't be shared with a client via `getWork()` and `getJob()`. Be sure not to publish cursors that return `job._private`!
* Added support for `@scrub` hook function to sanitize documents before validating them in `getWork()` and `getJob()`
* Refactor JobCollection classes
* Added support for Meteor 0.9.x style packages, including name change to accomodate

### v.0.0.16

* Updated to use the latest version of the `meteor-job` npm package

### v.0.0.15

* Added `until` option for `job.repeat()`, `job.retry()`, job.restart() and job.rerun().
* Added `jc.foreverDate` to indicate a Date that will never come
* Fixed bug where `jc.forever` was not available
* Default Date for `job.after()` is now based on the server clock, not the clock of the machine creating the job. (thanks @daeq)
* Added `created` field to job document model to keep track of when a job was first created on the server

### v.0.0.14

* Added `idGeneration` and `noCollectionSuffix` options to JobCollection constructor. Thanks to @mitar for suggestions.
* Removed unnecessary console log outputs
* Updated README to point to new sample app, and to clarify the use of `jc.promote()` in Meteor multi-instance deployments.

### v0.0.13

* Fixed bugs in client simulations of stopJobs and startJobs DDP methods

### v0.0.12

* Fixed bug due to removal of validNumGTEOne

### v0.0.11

* Fixed bug in jobProgress due to missing validNumGTZero

### v0.0.10

* Changed the default value of `job.save()` `cancelRepeats` option to be `false`.
* Fixed a case where the `echo` options to `job.log()` could be sent to the server, resulting in failure of the operation.
* Documentation improvements courtesy of @dandv.

### v0.0.9

* Added `backoff` option to `job.retry()`. Implements resolves enhancement request [#2](https://github.com/vsivsi/meteor-job-collection/issues/2)

### v0.0.8

* Fixed bug introduced by "integer enforcement" change in v0.0.7. Integers may now be up to 53-bits (the Javascript maxInt). Fixes [#3](https://github.com/vsivsi/meteor-job-collection/issues/3)
* Fixed sort inversion of priority levels in `getWork()`. Fixes [#4](https://github.com/vsivsi/meteor-job-collection/issues/4)
* Thanks to @chhib for reporting the above two issues.

### v0.0.7

* Bumped meteor-job version to 0.0.9, fixing several bugs in Meteor.server and Meteor.client workers handling.
* Corrected validation of jobDocuments for non-negative integer attributes (integer enforcement was missing).
* jc.promote() formerly had a minimum valid polling rate of 1000ms, now any value > 0ms is valid
* Added a few more acceptance tests including client and server scheduling and running of a job.
* Documentation improvements

### v0.0.6

* Added initial testing harness
* Fixed issue with collection root name in DDP method naming.
* Changed evaluation of allow/deny rules so deny rules run first, just like in Meteor.
* Documentation improvements.

### v0.0.5

* Really fixed issue #1, thanks again to @chhib for reporting this.

### v0.0.4

* Test release debugging git submodule issues around issue #1

### v0.0.3

* Fixed issue #1, thanks to @chhib for reporting this.

### v0.0.2

* Documentation improvements
* Removed meteor-job subproject and added npm dependency on it instead

### v0.0.1

* Initial revision.
