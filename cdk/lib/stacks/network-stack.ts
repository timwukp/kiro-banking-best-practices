import * as cdk from 'aws-cdk-lib';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import { Construct } from 'constructs';
import { KiroBankingConfig } from '../../config/environments';

/**
 * Network Stack: VPC with PrivateLink endpoints for Kiro.
 *
 * MAS TRM Section 11.2 (Network Security):
 * - Private subnets only (no public subnets)
 * - VPC Interface Endpoints for Kiro services (AWS PrivateLink)
 * - Security groups restricting traffic to HTTPS only
 * - Network ACLs for defense-in-depth
 * - VPC Flow Logs for network monitoring
 *
 * Architecture:
 *   Corporate VPC (10.0.0.0/16)
 *   ├── Private Subnet A (10.0.1.0/24) - WorkSpaces
 *   ├── Private Subnet B (10.0.2.0/24) - WorkSpaces
 *   ├── Isolated Subnet C (10.0.3.0/24) - VPC Endpoints
 *   └── Isolated Subnet D (10.0.4.0/24) - VPC Endpoints
 */
export interface NetworkStackProps extends cdk.StackProps {
  readonly config: KiroBankingConfig;
}

export class NetworkStack extends cdk.Stack {
  public readonly vpc: ec2.Vpc;
  public readonly endpointSecurityGroup: ec2.SecurityGroup;
  public readonly workspacesSecurityGroup: ec2.SecurityGroup;

  constructor(scope: Construct, id: string, props: NetworkStackProps) {
    super(scope, id, props);

    const { config } = props;

    // --- VPC: Private-only, no NAT Gateway, no Internet Gateway ---
    this.vpc = new ec2.Vpc(this, 'KiroVpc', {
      vpcName: `kiro-banking-vpc-${config.environment}`,
      ipAddresses: ec2.IpAddresses.cidr(config.vpcCidr),
      maxAzs: 2,
      natGateways: 0, // No internet access - Zero Trust
      subnetConfiguration: [
        {
          cidrMask: 24,
          name: 'Workspaces',
          subnetType: ec2.SubnetType.PRIVATE_ISOLATED,
        },
        {
          cidrMask: 24,
          name: 'Endpoints',
          subnetType: ec2.SubnetType.PRIVATE_ISOLATED,
        },
      ],
      flowLogs: {
        'VpcFlowLogs': {
          destination: ec2.FlowLogDestination.toCloudWatchLogs(),
          trafficType: ec2.FlowLogTrafficType.ALL,
        },
      },
    });

    // --- Security Group: VPC Endpoints ---
    this.endpointSecurityGroup = new ec2.SecurityGroup(this, 'EndpointSG', {
      vpc: this.vpc,
      securityGroupName: `kiro-vpc-endpoint-sg-${config.environment}`,
      description: 'Security group for Kiro VPC endpoints - HTTPS only from WorkSpaces',
      allowAllOutbound: false,
    });

    // --- Security Group: WorkSpaces ---
    this.workspacesSecurityGroup = new ec2.SecurityGroup(this, 'WorkspacesSG', {
      vpc: this.vpc,
      securityGroupName: `kiro-workspaces-sg-${config.environment}`,
      description: 'Security group for WorkSpaces - outbound to VPC endpoints only',
      allowAllOutbound: false,
    });

    // WorkSpaces -> VPC Endpoints (HTTPS only)
    this.workspacesSecurityGroup.addEgressRule(
      this.endpointSecurityGroup,
      ec2.Port.tcp(443),
      'Allow HTTPS to Kiro VPC endpoints',
    );

    // VPC Endpoints accept from WorkSpaces (HTTPS only)
    this.endpointSecurityGroup.addIngressRule(
      this.workspacesSecurityGroup,
      ec2.Port.tcp(443),
      'Allow HTTPS from WorkSpaces',
    );

    // --- VPC Interface Endpoints for Kiro Services ---
    const endpointSubnets: ec2.SubnetSelection = {
      subnetGroupName: 'Endpoints',
    };

    for (const serviceName of config.kiroEndpoints) {
      const endpointId = serviceName.split('.').pop() || 'unknown';

      new ec2.InterfaceVpcEndpoint(this, `Endpoint-${endpointId}`, {
        vpc: this.vpc,
        service: new ec2.InterfaceVpcEndpointService(serviceName, 443),
        subnets: endpointSubnets,
        securityGroups: [this.endpointSecurityGroup],
        privateDnsEnabled: true,
        open: false,
      });
    }

    // --- Additional AWS Service Endpoints (required for operations) ---

    // S3 Gateway Endpoint (for CloudTrail logs, artifacts)
    this.vpc.addGatewayEndpoint('S3Endpoint', {
      service: ec2.GatewayVpcEndpointAwsService.S3,
    });

    // CloudWatch Logs endpoint (for VPC flow logs, CloudTrail)
    new ec2.InterfaceVpcEndpoint(this, 'CloudWatchLogsEndpoint', {
      vpc: this.vpc,
      service: ec2.InterfaceVpcEndpointAwsService.CLOUDWATCH_LOGS,
      subnets: endpointSubnets,
      securityGroups: [this.endpointSecurityGroup],
      privateDnsEnabled: true,
      open: false,
    });

    // KMS endpoint (for encryption operations)
    new ec2.InterfaceVpcEndpoint(this, 'KmsEndpoint', {
      vpc: this.vpc,
      service: ec2.InterfaceVpcEndpointAwsService.KMS,
      subnets: endpointSubnets,
      securityGroups: [this.endpointSecurityGroup],
      privateDnsEnabled: true,
      open: false,
    });

    // SSO/Identity Center endpoint
    new ec2.InterfaceVpcEndpoint(this, 'SsoEndpoint', {
      vpc: this.vpc,
      service: ec2.InterfaceVpcEndpointAwsService.SSO,
      subnets: endpointSubnets,
      securityGroups: [this.endpointSecurityGroup],
      privateDnsEnabled: true,
      open: false,
    });

    // STS endpoint (for credential operations)
    new ec2.InterfaceVpcEndpoint(this, 'StsEndpoint', {
      vpc: this.vpc,
      service: ec2.InterfaceVpcEndpointAwsService.STS,
      subnets: endpointSubnets,
      securityGroups: [this.endpointSecurityGroup],
      privateDnsEnabled: true,
      open: false,
    });

    // --- Network ACLs (defense-in-depth) ---
    const endpointNacl = new ec2.NetworkAcl(this, 'EndpointNacl', {
      vpc: this.vpc,
      networkAclName: `kiro-endpoint-nacl-${config.environment}`,
    });

    // Inbound: Allow HTTPS from VPC CIDR
    endpointNacl.addEntry('InboundHttps', {
      ruleNumber: 100,
      cidr: ec2.AclCidr.ipv4(config.vpcCidr),
      traffic: ec2.AclTraffic.tcpPort(443),
      direction: ec2.TrafficDirection.INGRESS,
      ruleAction: ec2.Action.ALLOW,
    });

    // Inbound: Allow ephemeral return traffic
    endpointNacl.addEntry('InboundEphemeral', {
      ruleNumber: 110,
      cidr: ec2.AclCidr.ipv4(config.vpcCidr),
      traffic: ec2.AclTraffic.tcpPortRange(1024, 65535),
      direction: ec2.TrafficDirection.INGRESS,
      ruleAction: ec2.Action.ALLOW,
    });

    // Outbound: Allow HTTPS to VPC CIDR
    endpointNacl.addEntry('OutboundHttps', {
      ruleNumber: 100,
      cidr: ec2.AclCidr.ipv4(config.vpcCidr),
      traffic: ec2.AclTraffic.tcpPort(443),
      direction: ec2.TrafficDirection.EGRESS,
      ruleAction: ec2.Action.ALLOW,
    });

    // Outbound: Allow ephemeral ports
    endpointNacl.addEntry('OutboundEphemeral', {
      ruleNumber: 110,
      cidr: ec2.AclCidr.ipv4(config.vpcCidr),
      traffic: ec2.AclTraffic.tcpPortRange(1024, 65535),
      direction: ec2.TrafficDirection.EGRESS,
      ruleAction: ec2.Action.ALLOW,
    });

    // --- Outputs ---
    new cdk.CfnOutput(this, 'VpcId', {
      value: this.vpc.vpcId,
      description: 'VPC ID for Kiro banking environment',
      exportName: `KiroBanking-VpcId-${config.environment}`,
    });

    new cdk.CfnOutput(this, 'EndpointSecurityGroupId', {
      value: this.endpointSecurityGroup.securityGroupId,
      description: 'Security group ID for VPC endpoints',
    });

    new cdk.CfnOutput(this, 'WorkspacesSecurityGroupId', {
      value: this.workspacesSecurityGroup.securityGroupId,
      description: 'Security group ID for WorkSpaces',
    });
  }
}
