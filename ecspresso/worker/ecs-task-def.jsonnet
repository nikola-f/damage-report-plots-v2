local tfstate = std.native('tfstate');
local appName = std.extVar('APP_NAME');
local env = std.extVar('ENV');
local imageTag = std.extVar('IMAGE_TAG');

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
      image: tfstate('output.ecr_repository_url') + ':' + imageTag,
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
      image: tfstate('output.ecr_repository_url') + ':' + imageTag,
      command: ['bundle', 'exec', 'sidekiq'],
      essential: true,
      readonlyRootFilesystem: true,
      dependsOn: [{ containerName: 'setup', condition: 'SUCCESS' }],
      mountPoints: [
        { sourceVolume: 'tmp', containerPath: '/tmp', readOnly: false },
        { sourceVolume: 'app-tmp', containerPath: '/app/tmp', readOnly: false },
      ],
      environment: [
        { name: 'RAILS_ENV', value: 'production' },
        { name: 'ALLOWED_ORIGINS', value: tfstate('output.allowed_origins') },
        { name: 'SQS_THREAD_IDS_QUEUE_URL', value: tfstate('output.sqs_thread_ids_queue_url') },
        { name: 'SQS_REPORTS_QUEUE_URL', value: tfstate('output.sqs_reports_queue_url') },
      ] + (if env == 'dev' then [{ name: 'RAILS_LOG_LEVEL', value: 'debug' }] else []),
      secrets: [
        {
          name: 'RAILS_MASTER_KEY',
          valueFrom: tfstate('output.rails_master_key_secret_arn'),
        },
        {
          name: 'REDIS_URL',
          valueFrom: tfstate('output.redis_url_secret_arn'),
        },
      ],
      logConfiguration: {
        logDriver: 'awslogs',
        options: {
          'awslogs-group': tfstate('output.log_group_worker'),
          'awslogs-region': tfstate('output.aws_region'),
          'awslogs-stream-prefix': 'ecs',
        },
      },
    },
  ],
}
