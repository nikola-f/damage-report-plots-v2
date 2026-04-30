local tfstate = std.native('tfstate');

{
  desiredCount: 1,
  launchType: 'FARGATE',
  networkConfiguration: {
    awsvpcConfiguration: {
      subnets: std.split(tfstate('output.public_subnet_ids_csv'), ','),
      securityGroups: [tfstate('output.ecs_security_group_id')],
      assignPublicIp: 'ENABLED',
    },
  },
  loadBalancers: [
    {
      targetGroupArn: tfstate('output.web_target_group_arn'),
      containerName: 'web',
      containerPort: 3000,
    },
  ],
  deploymentConfiguration: {
    minimumHealthyPercent: 50,
    maximumPercent: 200,
  },
  enableExecuteCommand: true,
}
