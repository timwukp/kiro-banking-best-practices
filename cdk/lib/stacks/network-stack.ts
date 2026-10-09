import * as cdk from 'aws-cdk-lib';
import { Annotations } from 'aws-cdk-lib';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as route53resolver from 'aws-cdk-lib/aws-route53resolver';
import { Construct } from 'constructs';
import { NagSuppressions } from 'cdk-nag';
import { EGRESS_MODES, KiroBankingConfig } from '../../config/environments';
import {
  DEFAULT_IDENTITY_CENTER_REGION,
  KIRO_PROFILE_REGIONS,
  isKiroProfileRegion,
  isValidDnsFirewallDomain,
  kiroEgressDomains,
  kiroInterfaceEndpointServices,
  uniqueLowerCase,
} from '../../config/kiro-endpoints';

/**
 * Network Stack: VPC for WorkSpaces with VPC endpoints and optional filtered
 * egress for Kiro.
 *
 * MAS TRM Section 11.2 (Network Security):
 * - No internet path by default (isolated subnets, no internet gateway, no NAT)
 * - VPC interface endpoints (AWS PrivateLink) for the AWS APIs used in this VPC,
 *   and for Kiro when the workload region is the Kiro profile region
 * - Security groups with HTTPS-only rules (see the NOTE on WorkspacesSG about
 *   EC2's default egress rule)
 * - Network ACL with HTTPS-only entries for defense-in-depth (see the NOTE at
 *   the NACL below)
 * - VPC Flow Logs for network monitoring (TRM 12.2)
 *
 * Kiro connectivity: Kiro endpoints exist only in the Kiro profile regions
 * (us-east-1, eu-central-1; see config/kiro-endpoints.ts), so none are created
 * in ap-southeast-1. Kiro sign-in, downloads and app.kiro.dev are public HTTPS
 * hosts in every region. Kiro clients therefore always need allowlisted HTTPS
 * egress: central egress (egress.mode = 'none', recommended) or the
 * self-contained egress.mode = 'nat-dns-firewall'.
 *
 * Subnet layout (2 AZs; dev CIDRs shown, prod uses 10.1.0.0/16):
 *   VPC 10.0.0.0/16
 *   ├── Workspaces 10.0.0.0/24, 10.0.1.0/24   isolated ('none') or private with
 *   │                                          NAT egress ('nat-dns-firewall')
 *   ├── Endpoints  10.0.2.0/24, 10.0.3.0/24   isolated, VPC interface endpoints
 *   └── Public     10.0.4.0/28, 10.0.4.16/28  'nat-dns-firewall' only (NAT gateway)
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
    const region = this.region;

    if (cdk.Token.isUnresolved(region)) {
      throw new Error('NetworkStack needs an explicit env.region to decide which Kiro endpoints exist in that region');
    }
    if (!isKiroProfileRegion(config.kiroProfileRegion)) {
      throw new Error(`kiroProfileRegion must be one of ${KIRO_PROFILE_REGIONS.join(', ')}; got '${config.kiroProfileRegion}'`);
    }
    if (!EGRESS_MODES.includes(config.egress.mode)) {
      throw new Error(`egress.mode must be one of ${EGRESS_MODES.join(', ')}; got '${config.egress.mode}'`);
    }
    const natEgress = config.egress.mode === 'nat-dns-firewall';

    // --- VPC ---
    // egress.mode 'none': private-only, no NAT gateway, no internet gateway.
    // egress.mode 'nat-dns-firewall': the Public subnet group is appended last
    // so the Workspaces and Endpoints CIDRs stay the same in both modes.
    const subnetConfiguration: ec2.SubnetConfiguration[] = [
      {
        cidrMask: 24,
        name: 'Workspaces',
        subnetType: natEgress ? ec2.SubnetType.PRIVATE_WITH_EGRESS : ec2.SubnetType.PRIVATE_ISOLATED,
      },
      {
        cidrMask: 24,
        name: 'Endpoints',
        subnetType: ec2.SubnetType.PRIVATE_ISOLATED,
      },
    ];
    if (natEgress) {
      subnetConfiguration.push({
        cidrMask: 28,
        name: 'Public',
        subnetType: ec2.SubnetType.PUBLIC,
        // The subnets only host the NAT gateway (which uses an Elastic IP).
        mapPublicIpOnLaunch: false,
      });
    }

    this.vpc = new ec2.Vpc(this, 'KiroVpc', {
      vpcName: `kiro-banking-vpc-${config.environment}`,
      ipAddresses: ec2.IpAddresses.cidr(config.vpcCidr),
      maxAzs: 2,
      // 'none': no internet access (Zero Trust). 'nat-dns-firewall': one NAT
      // gateway to limit cost; use one per AZ for production resilience.
      natGateways: natEgress ? 1 : 0,
      subnetConfiguration,
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
    // The description is kept unchanged in every egress mode: changing it would
    // force a replacement, which fails because the group name is fixed.
    // NOTE: in egress.mode 'none' the only egress rule is the separate
    // security-group-to-security-group rule below, so the template has no inline
    // egress rule and EC2 keeps its default allow-all egress rule on this group
    // (the isolated subnets still have no route to the internet).
    // In 'nat-dns-firewall' mode the inline HTTPS rule replaces the default rule.
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

    // --- VPC Interface Endpoints ---
    const endpointSubnets: ec2.SubnetSelection = {
      subnetGroupName: 'Endpoints',
    };

    // Hostnames answered by the interface endpoints' private DNS. They resolve
    // to private IPs in this VPC and are allowlisted in DNS Firewall.
    const privateEndpointHosts: string[] = [];
    const addInterfaceEndpoint = (endpointId: string, service: ec2.IInterfaceVpcEndpointService, privateDnsHost: string) => {
      new ec2.InterfaceVpcEndpoint(this, endpointId, {
        vpc: this.vpc,
        service,
        subnets: endpointSubnets,
        securityGroups: [this.endpointSecurityGroup],
        privateDnsEnabled: true,
        open: false,
      });
      privateEndpointHosts.push(privateDnsHost);
    };

    // Kiro endpoints: only when this stack is in the Kiro profile region.
    const availableKiroServices = region === config.kiroProfileRegion ? kiroInterfaceEndpointServices(region) : [];
    const unknownKiroServices = config.kiroEndpoints.filter((s) => !availableKiroServices.includes(s));
    if (unknownKiroServices.length > 0) {
      throw new Error(
        `kiroEndpoints lists services that do not exist for this stack (region ${region}, kiroProfileRegion ` +
        `${config.kiroProfileRegion}): ${unknownKiroServices.join(', ')}. Kiro endpoints exist only in ` +
        `${KIRO_PROFILE_REGIONS.join(' and ')}; leave kiroEndpoints empty to derive them.`,
      );
    }
    const kiroServices = config.kiroEndpoints.length > 0 ? config.kiroEndpoints : availableKiroServices;

    for (const serviceName of kiroServices) {
      const endpointId = serviceName.split('.').pop() || 'unknown';
      addInterfaceEndpoint(
        `Endpoint-${endpointId}`,
        new ec2.InterfaceVpcEndpointService(serviceName, 443),
        `${endpointId}.${region}.amazonaws.com`,
      );
    }

    if (kiroServices.length === 0) {
      Annotations.of(this).addInfo(
        `No Kiro VPC interface endpoints are created: the workload region (${region}) is not the Kiro profile ` +
        `region (${config.kiroProfileRegion}). Kiro PrivateLink endpoints exist only in the Kiro profile regions ` +
        `(${KIRO_PROFILE_REGIONS.join(', ')}) and cross-Region PrivateLink does not support them. Kiro clients ` +
        'reach Kiro over HTTPS: allowlist the hosts from kiroEgressDomains() on a central egress VPC or proxy, ' +
        "or set egress.mode = 'nat-dns-firewall'. For private API connectivity, use a Kiro access VPC in the " +
        'profile region (see cdk/README.md).',
      );
    }
    if (!natEgress) {
      Annotations.of(this).addInfo(
        "egress.mode is 'none': this VPC has no internet gateway or NAT gateway. Kiro sign-in (app.kiro.dev, " +
        'IAM Identity Center) and download hosts are public HTTPS endpoints, so provide egress through a central ' +
        'egress/inspection VPC or proxy that enforces the Kiro allowlist (kiroEgressDomains()).',
      );
    }

    // --- Additional AWS Service Endpoints (for workloads in this VPC) ---
    // CloudTrail and VPC Flow Logs are delivered by the AWS services themselves
    // and do not use these endpoints.

    // S3 gateway endpoint: private S3 access from this VPC (e.g. installers, artifacts).
    // In 'nat-dns-firewall' mode, add the specific bucket hostnames you need to
    // egress.allowedDomains; S3 wildcards are not allowlisted.
    this.vpc.addGatewayEndpoint('S3Endpoint', {
      service: ec2.GatewayVpcEndpointAwsService.S3,
    });

    // CloudWatch Logs: log delivery from agents in this VPC (e.g. the CloudWatch agent)
    addInterfaceEndpoint(
      'CloudWatchLogsEndpoint',
      ec2.InterfaceVpcEndpointAwsService.CLOUDWATCH_LOGS,
      `${ec2.InterfaceVpcEndpointAwsService.CLOUDWATCH_LOGS.shortName}.${region}.amazonaws.com`,
    );

    // KMS: encryption API calls from workloads in this VPC
    addInterfaceEndpoint(
      'KmsEndpoint',
      ec2.InterfaceVpcEndpointAwsService.KMS,
      `${ec2.InterfaceVpcEndpointAwsService.KMS.shortName}.${region}.amazonaws.com`,
    );

    // Identity Store API (identitystore.<region>.amazonaws.com) for user and group
    // administration and provisioning automation. It is NOT used for Kiro sign-in,
    // which uses the public IAM Identity Center sign-in, portal and OIDC hosts
    // (identityCenterHosts() in config/kiro-endpoints.ts). The construct ID
    // 'SsoEndpoint' is kept so that the deployed endpoint is not replaced.
    addInterfaceEndpoint(
      'SsoEndpoint',
      ec2.InterfaceVpcEndpointAwsService.IAM_IDENTITY_CENTER,
      `${ec2.InterfaceVpcEndpointAwsService.IAM_IDENTITY_CENTER.shortName}.${region}.amazonaws.com`,
    );

    // STS: credential operations (e.g. AssumeRole) from workloads in this VPC
    addInterfaceEndpoint(
      'StsEndpoint',
      ec2.InterfaceVpcEndpointAwsService.STS,
      `${ec2.InterfaceVpcEndpointAwsService.STS.shortName}.${region}.amazonaws.com`,
    );

    // --- Filtered egress (egress.mode = 'nat-dns-firewall') ---
    if (natEgress) {
      // Port 443 to any IPv4 address: destinations are restricted by name through
      // Route 53 Resolver DNS Firewall below, not by IP.
      this.workspacesSecurityGroup.addEgressRule(
        ec2.Peer.anyIpv4(),
        ec2.Port.tcp(443),
        'HTTPS egress via NAT gateway; hostnames restricted by Route 53 Resolver DNS Firewall',
      );
      this.addEgressDnsFirewall(config, privateEndpointHosts);
    }

    // --- Network ACLs (defense-in-depth) ---
    // NOTE: this NACL has no subnet association, so its entries do not filter
    // traffic yet. Associating it (e.g. subnetSelection: { subnetGroupName:
    // 'Endpoints' }) changes the deployed network; test that change first.
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

    // CDK Nag suppressions - NACLs are intentional for MAS TRM 11.2 defense-in-depth
    NagSuppressions.addResourceSuppressions(endpointNacl, [
      {
        id: 'AwsSolutions-VPC3',
        reason: 'NACLs are required for MAS TRM Section 11.2 defense-in-depth network security alongside security groups',
      },
    ], true);

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

  /**
   * Route 53 Resolver DNS Firewall in "walled garden" form: resolve only the
   * Kiro allowlist, the private DNS names of this VPC's interface endpoints and
   * egress.allowedDomains; answer every other query with NODATA.
   *
   * Limitation: DNS Firewall filters DNS queries only. It does not stop a
   * client that connects to an IP address directly, including DNS over HTTPS
   * to a public resolver IP on port 443. For stronger enforcement use
   * AWS Network Firewall with TLS SNI inspection or an explicit proxy in a
   * central inspection VPC.
   */
  private addEgressDnsFirewall(config: KiroBankingConfig, privateEndpointHosts: string[]): void {
    const invalidDomains = config.egress.allowedDomains.filter((d) => !isValidDnsFirewallDomain(d));
    if (invalidDomains.length > 0) {
      throw new Error(
        `egress.allowedDomains contains invalid DNS Firewall domains: ${invalidDomains.join(', ')}. ` +
        "Use hostnames such as 'updates.example.com' or '*.example.com' (a bare '*' would disable filtering).",
      );
    }

    const allowedDomains = uniqueLowerCase([
      ...kiroEgressDomains({
        identityCenterRegion: config.identityCenterRegion ?? DEFAULT_IDENTITY_CENTER_REGION,
        identityCenterPortalHost: config.identityCenterPortalHost,
        externalIdpDomain: config.externalIdpDomain,
      }),
      // Without these, DNS Firewall would also block this VPC's own endpoints.
      ...privateEndpointHosts,
      ...config.egress.allowedDomains,
    ]);

    const allowList = new route53resolver.CfnFirewallDomainList(this, 'EgressAllowDomainList', {
      name: `kiro-banking-egress-allow-${config.environment}`,
      domains: allowedDomains,
    });

    const blockAllList = new route53resolver.CfnFirewallDomainList(this, 'EgressBlockAllDomainList', {
      name: `kiro-banking-egress-block-all-${config.environment}`,
      domains: ['*'],
    });

    const ruleGroup = new route53resolver.CfnFirewallRuleGroup(this, 'EgressDnsFirewallRuleGroup', {
      name: `kiro-banking-egress-${config.environment}`,
      firewallRules: [
        {
          action: 'ALLOW',
          priority: 100,
          firewallDomainListId: allowList.attrId,
          // Trust CNAME/DNAME targets of allowlisted names (e.g. CDN hostnames);
          // otherwise the block-all rule would drop them.
          firewallDomainRedirectionAction: 'TRUST_REDIRECTION_DOMAIN',
        },
        {
          action: 'BLOCK',
          priority: 200,
          firewallDomainListId: blockAllList.attrId,
          blockResponse: 'NODATA',
        },
      ],
    });

    new route53resolver.CfnFirewallRuleGroupAssociation(this, 'EgressDnsFirewallAssociation', {
      name: `kiro-banking-egress-${config.environment}`,
      firewallRuleGroupId: ruleGroup.attrId,
      vpcId: this.vpc.vpcId,
      // Allowed association priorities are 101-9899; lower numbers are evaluated first.
      priority: 101,
    });
  }
}
