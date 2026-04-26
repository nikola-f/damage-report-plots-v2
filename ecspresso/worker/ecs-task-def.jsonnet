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
  cpu: '512',
  memory: '1024',
  containerDefinitions: [
    {
      name: 'worker',
      image: tfstate('output.ecr_repository_url') + ':' + imageTag,
      command: ['bundle', 'exec', 'sidekiq'],
      essential: true,
      environment: [
        { name: 'RAILS_ENV', value: 'production' },
        { name: 'REDIS_URL', value: tfstate('output.redis_url') },
        { name: 'ALLOWED_ORIGINS', value: tfstate('output.allowed_origins') },
        { name: 'SQS_THREAD_IDS_QUEUE_URL', value: tfstate('output.sqs_thread_ids_queue_url') },
        { name: 'SQS_REPORTS_QUEUE_URL', value: tfstate('output.sqs_reports_queue_url') },
      ],
      secrets: [
        {
          name: 'RAILS_MASTER_KEY',
          valueFrom: tfstate('output.rails_master_key_secret_arn'),
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
