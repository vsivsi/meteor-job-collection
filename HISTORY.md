## Revision history

### 0.0.9

*    Added `backoff` option to `job.retry()`. Implements resolves enhancement request [#2](https://github.com/vsivsi/meteor-job-collection/issues/2)

### 0.0.8

*    Fixed bug introduced by "integer enforcement" change in v0.0.7. Integers may now be up to 53-bits (the Javascript maxInt). Fixes [#3](https://github.com/vsivsi/meteor-job-collection/issues/3)
*    Fixed sort inversion of priority levels in `getWork()`. Fixes [#4](https://github.com/vsivsi/meteor-job-collection/issues/4)
*    Thanks to @chhib for reporting the above two issues.

### 0.0.7

*    Bumped meteor-job version to 0.0.9, fixing several bugs in Meteor.server and Meteor.client workers handling.
*    Corrected validation of jobDocuments for non-negative integer attributes (integer enforcement was missing).
*    jc.promote() formerly had a minimum valid polling rate of 1000ms, now any value > 0ms is valid
*    Added a few more acceptance tests including client and server scheduling and running of a job.
*    Documentation improvements

### 0.0.6

*    Added initial testing harness
*    Fixed issue with collection root name in DDP method naming.
*    Changed evaluation of allow/deny rules so deny rules run first, just like in Meteor.
*    Documentation improvements.

### 0.0.5

*    Really fixed issue #1, thanks again to @chhib for reporting this.

### 0.0.4

*    Test release debugging git submodule issues around issue #1

### 0.0.3

*    Fixed issue #1, thanks to @chhib for reporting this.

### 0.0.2

*    Documentation improvements
*    Removed meteor-job subproject and added npm dependency on it instead

### 0.0.1

*    Initial revision.
