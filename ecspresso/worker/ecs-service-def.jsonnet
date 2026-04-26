local tfstate = std.native('tfstate');

{
  desiredCount: 1,
  launchType: 'FARGATE',
  networkConfiguration: {
    awsvpcConfiguration: {
      subnets: std.split(tfstate('output.private_subnet_ids_csv'), ','),
      securityGroups: [tfstate('output.ecs_security_group_id')],
      assignPublicIp: 'DISABLED',
    },
  },
  deploymentConfiguration: {
    minimumHealthyPercent: 50,
    maximumPercent: 200,
  },
  enableExecuteCommand: true,
}
