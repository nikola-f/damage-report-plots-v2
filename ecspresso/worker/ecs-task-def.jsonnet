local tfstate = std.native('tfstate');
local appName = std.extVar('APP_NAME');
local env = std.extVar('ENV');
local imageTag = std.extVar('IMAGE_TAG');

// Rewrite an SQS queue URL to the dual-stack host so the SDK reaches SQS over
// IPv6. The SDK derives the endpoint from the queue URL host, which overrides
// AWS_USE_DUALSTACK_ENDPOINT, so the URL itself must point at the IPv6 endpoint.
local dualstackSqsUrl(url) = std.strReplace(url, '.amazonaws.com/', '.api.aws/');

{
  family: appName + '-' + env + '-worker',
  executionRoleArn: tfstate('output.task_execution_role_arn'),
  taskRoleArn: tfstate('output.task_role_arn'),
  networkMode: 'awsvpc',
  requiresCompatibilities: ['FARGATE'],
  runtimePlatform: {
    cpuArchitecture: 'ARM64',
    operatingSystemFamily: 'LINUX',
  },
  cpu: '256',
  memory: '512',
  volumes: [
    { name: 'tmp' },
    { name: 'app-tmp' },
  ],
  containerDefinitions: [
    {
      name: 'setup',
      image: tfstate('output.ecr_repository_url_dualstack') + ':' + imageTag,
      user: 'root',
      essential: false,
      command: ['sh', '-c', 'chown -R 1000:1000 /app/tmp /tmp'],
      mountPoints: [
        { sourceVolume: 'tmp', containerPath: '/tmp', readOnly: false },
        { sourceVolume: 'app-tmp', containerPath: '/app/tmp', readOnly: false },
      ],
    },
    {
      name: 'worker',
      image: tfstate('output.ecr_repository_url_dualstack') + ':' + imageTag,
      command: ['bundle', 'exec', 'sidekiq'],
      essential: true,
      readonlyRootFilesystem: true,
      stopTimeout: 120,
      dependsOn: [
        { containerName: 'setup', condition: 'SUCCESS' },
        { containerName: 'log_router', condition: 'START' },
      ],
      mountPoints: [
        { sourceVolume: 'tmp', containerPath: '/tmp', readOnly: false },
        { sourceVolume: 'app-tmp', containerPath: '/app/tmp', readOnly: false },
      ],
      environment: [
        { name: 'RAILS_ENV',                              value: 'production' },
        // Preload jemalloc for the sidekiq process. jemalloc returns freed
        // memory to the OS far more aggressively than glibc malloc and reduces
        // multi-threaded fragmentation, lowering the RSS high-water mark. The
        // soname is resolved via the ld.so cache (libjemalloc2 runs ldconfig on
        // install), so no arch-specific path is hardcoded. Replaces the previous
        // MALLOC_ARENA_MAX glibc tuning.
        { name: 'LD_PRELOAD',                             value: 'libjemalloc.so.2' },
        // Use AWS dual-stack endpoints (e.g. sqs.{region}.api.aws) so the SDK
        // reaches AWS over IPv6 from the IPv6-only task subnet.
        { name: 'AWS_USE_DUALSTACK_ENDPOINT',             value: 'true' },
        { name: 'ALLOWED_ORIGINS',                        value: tfstate('output.allowed_origins') },
        { name: 'SQS_THREAD_IDS_QUEUE_URL',               value: dualstackSqsUrl(tfstate('output.sqs_thread_ids_queue_url')) },
        { name: 'SQS_REPORTS_QUEUE_URL',                  value: dualstackSqsUrl(tfstate('output.sqs_reports_queue_url')) },
        { name: 'THREAD_BATCH_WORKER_POLL_INTERVAL',        value: tfstate('output.thread_batch_worker_poll_interval') },
        { name: 'THREAD_BATCH_WORKER_LOCK_TTL',             value: tfstate('output.thread_batch_worker_lock_ttl') },
        { name: 'THREAD_BATCH_WORKER_MAX_MESSAGES_PER_RUN', value: tfstate('output.thread_batch_worker_max_messages_per_run') },
        { name: 'SPREADSHEET_SYNC_WORKER_POLL_INTERVAL',    value: tfstate('output.spreadsheet_sync_worker_poll_interval') },
        { name: 'SPREADSHEET_SYNC_WORKER_LOCK_TTL',             value: tfstate('output.spreadsheet_sync_worker_lock_ttl') },
        { name: 'SPREADSHEET_SYNC_WORKER_MAX_MESSAGES_PER_RUN', value: tfstate('output.spreadsheet_sync_worker_max_messages_per_run') },
        { name: 'THREAD_LIST_WORKER_THREADS_PER_MESSAGE',    value: tfstate('output.thread_list_worker_threads_per_message') },
        { name: 'THREAD_LIST_WORKER_THREAD_ID_LIMIT',        value: tfstate('output.thread_list_worker_thread_id_limit') },
        { name: 'THREAD_BATCH_FETCHER_BATCH_SIZE',          value: tfstate('output.thread_batch_fetcher_batch_size') },
        { name: 'THREAD_BATCH_FETCHER_INTER_BATCH_SLEEP',   value: tfstate('output.thread_batch_fetcher_inter_batch_sleep') },
      ] + (if env == 'dev' then [{ name: 'RAILS_LOG_LEVEL', value: 'debug' }] else []),
      secrets: [
        { name: 'RAILS_MASTER_KEY', valueFrom: tfstate('output.rails_master_key_secret_arn') },
        { name: 'REDIS_URL',        valueFrom: tfstate('output.redis_url_secret_arn') },
      ],
      logConfiguration: {
        logDriver: 'awsfirelens',
        options: {
          Name: 'cloudwatch_logs',
          region: tfstate('output.aws_region'),
          log_group_name: tfstate('output.log_group_worker'),
          log_stream_prefix: 'ecs/',
          auto_create_group: 'false',
          // Dual-stack endpoint so logs reach CloudWatch over IPv6 (no Public IPv4)
          endpoint: 'logs.' + tfstate('output.aws_region') + '.api.aws',
        },
      },
    },
    {
      name: 'log_router',
      // Pulled over IPv6 from the ECR Public dual-stack endpoint
      image: 'ecr-public.aws.com/aws-observability/aws-for-fluent-bit:stable',
      essential: true,
      firelensConfiguration: {
        type: 'fluentbit',
      },
      // No logConfiguration: the router's own logs would otherwise need the
      // IPv4-only awslogs endpoint, which is unreachable without Public IPv4.
    },
  ],
}
