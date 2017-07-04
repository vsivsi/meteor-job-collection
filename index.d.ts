declare module 'meteor/vsivsi:job-collection' {
    import { WriteStream } from "fs";
    import { MongoObservable } from "meteor-rxjs";
    import { ScheduleData, Static } from "later";
    import Collection = MongoObservable.Collection;

    class JobDoc {
        _id: string;
        runId: string;
        type: string;
        status: 'waiting' | 'paused' | 'ready' | 'running' | 'failed' | 'cancelled' | 'completed';
        data: Object;
        result: Object;
        failures: Object[];
        priority: number;
        depends: string[];
        resolved: string[];
        after: Date;
        updated: Date;
        workTimeout: number;
        expiresAfter: Date;
        log: [ {
            time: Date,
            runId: string,
            level: 'info' | 'success' | 'warning' | 'danger';
            message: string,
            data: Object,
            progress: {
                completed: number,
                total: number,
                percent: number
            }
        } ];
        retries: number;
        retried: number;
        repeatRetries: number;
        retryUntil: Date;
        retryWait: number;
        retryBackoff: 'constant' | 'exponential';
        repeats: number;
        repeated: number;
        repeatUntil: Date;
        repeatWait: number | {
            schedules: Object[],
            exceptions?: Object[]
        };
        created: Date;
    }

    class JobCollection extends Collection<any> {

        logConsole: boolean;
        forever: any;
        foreverDate: any;
        jobPriorities: { low?: number, normal?: number, medium?: number, high?: number, critical?: number };
        jobStatuses: 'waiting' | 'paused' | 'ready' | 'running' | 'failed' | 'cancelled' | 'completed';
        jobRetryBackoffMethods: 'constant' | 'exponential';
        jobLogLevels: 'info' | 'success' | 'warning' | 'danger';
        jobStatusCancellable: 'running' | 'ready' | 'waiting' | 'paused';
        jobStatusPausable: 'ready' | 'waiting';
        jobStatusRemovable: 'cancelled' | 'completed' | 'failed';
        jobStatusRestartable: 'cancelled' | 'failed';
        ddpMethods: 'startJobServer' | 'shutdownJobServer' | 'jobRemove' | 'jobPause' | 'jobResume' | 'jobReady' | 'jobCancel' | 'jobRestart' | 'jobSave' | 'jobRerun' | 'getWork' | 'getJob' | 'jobLog' | 'jobProgress' | 'jobDone' | 'jobFail';
        ddpPermissionLevels: 'admin' | 'manager' | 'creator' | 'worker';
        ddpMethodPermissions: {
            'startJobServer': [ 'startJobServer' | 'admin' ],
            'shutdownJobServer': [ 'shutdownJobServer' | 'admin' ],
            'jobRemove': [ 'jobRemove' | 'admin' | 'manager' ],
            'jobPause': [ 'jobPause' | 'admin' | 'manager' ],
            'jobResume': [ 'jobResume' | 'admin' | 'manager' ],
            'jobReady': [ 'jobReady' | 'admin' | 'manager' ],
            'jobCancel': [ 'jobCancel' | 'admin' | 'manager' ],
            'jobRestart': [ 'jobRestart' | 'admin' | 'manager' ],
            'jobSave': [ 'jobSave' | 'admin' | 'creator' ],
            'jobRerun': [ 'jobRerun' | 'admin' | 'creator' ],
            'getWork': [ 'getWork' | 'admin' | 'worker' ],
            'getJob': [ 'getJob' | 'admin' | 'worker' ],
            'jobLog': [ 'jobLog' | 'admin' | 'worker' ],
            'jobProgress': [ 'jobProgress' | 'admin' | 'worker' ],
            'jobDone': [ 'jobDone' | 'admin' | 'worker' ],
            'jobFail': [ 'jobFail' | 'admin' | 'worker' ]
        };
        jobDocPattern: any;

        later: Static;

        constructor( name?: string, options?: { noCollectionSuffix?: boolean } );

        setLogStream( writeStream: WriteStream );

        promote( milliseconds: number );

        allow( options: Object );

        deny( options: Object );

        startJobServer( options?: {}, callback?: ( error: any, result: any ) => void ): boolean;

        shutdownJobServer( options?: { timeout?: number }, callback?: ( error: any, result: any ) => void ): boolean;

        getJob( id: string, options?: { getLog?: boolean }, callback?: ( error: any, result: any ) => void ): JobDoc;

        getJobs( ids: string[], options?: { getLog?: boolean }, callback?: ( error: any, result: any ) => void ): JobDoc[];

        getWork( type: string, options?: { maxJobs?: number, workTimeout?: number }, callback?: ( error: any, result: any ) => void ): JobDoc | JobDoc[];

        processJobs( type: string, options?: { concurrency?: number, payload?: number, pollInterval?: number, prefetch?: number, workTimeout?: number, callbackStrict?: boolean, errorCallback?: ( error: any ) => void }, worker?: ( result: Job, callback: any ) => void );

        readyJobs( ids: string[], options?: { force?: boolean, time?: number }, callback?: ( error: any, result: any ) => void ): boolean;

        pauseJobs( ids: string[], options?: Object, callback?: ( error: any, result: any ) => void ): boolean;

        resumeJobs( ids: string[], options?: Object, callback?: ( error: any, result: any ) => void ): boolean;

        cancelJobs( ids: string[], options?: Object, callback?: ( error: any, result: any ) => void ): boolean;

        restartJobs( ids: string[], options?: Object, callback?: ( error: any, result: any ) => void ): boolean;

        removeJobs( ids: string[], options?: Object, callback?: ( error: any, result: any ) => void ): boolean;
    }

    class Job {
        type: string;
        data: Object;
        doc: JobDoc;

        constructor( jc: JobCollection, type: string, options: Object );

        constructor( jc: JobCollection, jobDoc: JobDoc );

        depends( dependencies?: Job[] );

        priority( priority?: string | number ): Job;

        retry( options?: number | { retries?: number, until?: Date, wait?: number, backoff?: 'constant' | 'exponential' } ): Job;

        repeat( options?: number | { repeats?: number, until?: Date, wait?: number, schedule?: ScheduleData; } ): Job;

        delay( milliseconds?: number ): Job;

        after( time?: Date ): Job;

        log( message: string, options?: { level?: 'info' | 'success' | 'warning' | 'danger', data?: Object, echo?: boolean }, callback?: ( error: any, result: any ) => void ): boolean;

        progress( completed: number, total: number, options?: { echo: boolean }, callback?: ( error: any, result: any ) => void ): boolean;

        save( options?: { cancelRepeats: boolean }, callback?: ( error: any, result: any ) => void ): string;

        refresh( options?: { getLog?: boolean, getFailures?: boolean }, callback?: ( error: any, result: any ) => void ): Job;

        done( result: Object, options?: { repeatId?: boolean, delayDeps?: number }, callback?: ( error: any, result: any ) => void ): boolean;

        fail( error: Object, options?: { fatal?: boolean }, callback?: ( error: any, result: any ) => void ): boolean;

        pause( options?: Object, callback?: ( error: any, result: any ) => void ): boolean;

        resume( options?: Object, callback?: ( error: any, result: any ) => void ): boolean;

        ready( options?: { time?: Date, force?: boolean }, callback?: ( error: any, result: any ) => void ): boolean;

        cancel( options?: { antecedents?: boolean, dependents?: boolean }, callback?: ( error: any, result: any ) => void ): boolean;

        restart( options?: { retries?: number, until?: Date, antecedents?: boolean, dependents?: boolean }, callback?: ( error: any, result: any ) => void ): boolean;

        rerun( options?: { repeats?: number, until?: Date, wait?: number }, callback?: ( error: any, result: any ) => void ): string;

        remove( options?: Object, callback?: ( error: any, result: any ) => void ): boolean;
    }
}
