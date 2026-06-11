local tfstate = std.native('tfstate');
local appName = std.extVar('APP_NAME');
local env = std.extVar('ENV');
local imageTag = std.extVar('IMAGE_TAG');

{
  family: appName + '-' + env + '-web',
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
      name: 'web',
      image: tfstate('output.ecr_repository_url_dualstack') + ':' + imageTag,
      command: ['bundle', 'exec', 'rails', 'server', '-b', '0.0.0.0', '-p', '3000'],
      essential: true,
      readonlyRootFilesystem: true,
      dependsOn: [
        { containerName: 'setup', condition: 'SUCCESS' },
        { containerName: 'log_router', condition: 'START' },
      ],
      portMappings: [
        { containerPort: 3000, protocol: 'tcp' },
      ],
      mountPoints: [
        { sourceVolume: 'tmp', containerPath: '/tmp', readOnly: false },
        { sourceVolume: 'app-tmp', containerPath: '/app/tmp', readOnly: false },
      ],
      environment: [
        { name: 'RAILS_ENV', value: 'production' },
        // Use AWS dual-stack endpoints (e.g. sqs.{region}.api.aws) so the SDK
        // reaches AWS over IPv6 from the IPv6-only task subnet.
        { name: 'AWS_USE_DUALSTACK_ENDPOINT', value: 'true' },
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
        {
          name: 'GOOGLE_CLIENT_ID',
          valueFrom: tfstate('output.google_client_id_secret_arn'),
        },
        {
          name: 'GOOGLE_CLIENT_SECRET',
          valueFrom: tfstate('output.google_client_secret_secret_arn'),
        },
      ],
      logConfiguration: {
        logDriver: 'awsfirelens',
        options: {
          Name: 'cloudwatch_logs',
          region: tfstate('output.aws_region'),
          log_group_name: tfstate('output.log_group_web'),
          log_stream_prefix: 'ecs/',
          auto_create_group: 'false',
          // Dual-stack endpoint so logs reach CloudWatch over IPv6 (no Public IPv4)
          endpoint: 'logs.' + tfstate('output.aws_region') + '.api.aws',
        },
      },
      healthCheck: {
        command: ['CMD-SHELL', 'curl -f http://localhost:3000/up || exit 1'],
        interval: 30,
        timeout: 5,
        retries: 3,
        startPeriod: 60,
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
