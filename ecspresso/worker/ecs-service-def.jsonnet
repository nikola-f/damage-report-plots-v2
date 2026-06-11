local tfstate = std.native('tfstate');

{
  desiredCount: 1,
  capacityProviderStrategy: [
    { capacityProvider: 'FARGATE_SPOT', weight: 1, base: 0 },
  ],
  networkConfiguration: {
    awsvpcConfiguration: {
      subnets: std.split(tfstate('output.ipv6_subnet_ids_csv'), ','),
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
