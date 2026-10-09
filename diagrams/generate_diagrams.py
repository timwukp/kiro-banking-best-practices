"""
Optional PNG export of the architecture diagrams for AWS Kiro in FSI Best Practices.

The README embeds the same three diagrams as Mermaid blocks, which GitHub renders
natively; those are the maintained versions. Use this script only when you need
PNG files (slides, offline documents). Keep the labels in sync with the Mermaid
blocks in README.md (Security Architecture section).

How to run:
    pip install diagrams                  # the Python "diagrams" package
    brew install graphviz                 # or: apt-get install graphviz (provides `dot`)
    cd diagrams && python3 generate_diagrams.py

Output (current directory): architecture-option-a.png, architecture-option-b.png,
security-layers.png. The README does not reference these files.
"""
from diagrams import Diagram, Cluster, Edge
from diagrams.aws.enduser import Workspaces
from diagrams.aws.general import General, User
from diagrams.aws.management import Cloudtrail, Cloudwatch, Config as AwsConfig
from diagrams.aws.network import Endpoint, NATGateway, VPC
from diagrams.aws.security import DirectoryService, Guardduty, KMS, SingleSignOn
from diagrams.aws.storage import S3
from diagrams.onprem.client import Client, Users

GRAPH_ATTR = {"fontsize": "14", "bgcolor": "white", "pad": "0.5"}
PROFILE_REGION = "Kiro profile region\n(us-east-1 or eu-central-1)"

# --- Option A: Via IAM Identity Center ---
with Diagram(
    "Option A: Via AWS IAM Identity Center",
    filename="architecture-option-a",
    show=False,
    direction="TB",
    graph_attr=GRAPH_ATTR,
):
    idp = Users("Enterprise IdP\n(Entra ID or Okta, MFA)")
    dev = User("Developer")
    subscription = General("Kiro subscription\n(assigned in the Kiro console)")

    with Cluster("Identity region, e.g. ap-southeast-1"):
        idc = SingleSignOn("IAM Identity Center")

    with Cluster("Workload account, ap-southeast-1"):
        with Cluster("Private VPC: no public subnets, no inbound access"):
            vdi = Workspaces("WorkSpaces VDI\n(DLP, GPO)")
            kiro_client = Client("Kiro IDE / CLI")
            policy = General("Admin policy\nmanaged-settings.json\n(on the VDI image)")
            aws_endpoints = Endpoint("AWS service endpoints\n(logs, kms, sts, s3)")
        egress = NATGateway("Allowlisted HTTPS egress\n(sign-in, downloads, Kiro APIs)")
        with Cluster("Monitoring"):
            trail = Cloudtrail("CloudTrail")
            cw = Cloudwatch("CloudWatch")
            gd = Guardduty("GuardDuty")
            cfg = AwsConfig("AWS Config")
            kms = KMS("Customer-managed\nKMS keys")

    with Cluster(PROFILE_REGION):
        kiro = General("Kiro service\n(stores and processes\nprompts and code context)")
        prompt_logs = S3("Prompt logs and\nuser activity reports")

    idp >> Edge(label="SAML 2.0 + SCIM") >> idc
    idc >> Edge(label="users and groups") >> subscription >> kiro
    dev >> vdi >> kiro_client
    policy >> Edge(style="dashed", label="enforced by the Kiro client") >> kiro_client
    vdi >> aws_endpoints >> trail
    kiro_client >> egress >> Edge(label="HTTPS 443") >> kiro
    kiro >> prompt_logs

# --- Option B: Direct IdP Federation ---
with Diagram(
    "Option B: Direct IdP Federation (No IAM Identity Center)",
    filename="architecture-option-b",
    show=False,
    direction="TB",
    graph_attr=GRAPH_ATTR,
):
    idp = Users("Enterprise IdP\n(Okta or Entra ID, MFA)")
    dev = User("Developer")

    with Cluster("Workload account, ap-southeast-1"):
        directory = DirectoryService("AWS Directory Service\n(Managed AD, Simple AD\nor AD Connector)")
        with Cluster("Private VPC: no public subnets, no inbound access"):
            vdi = Workspaces("WorkSpaces VDI\n(DLP, GPO)")
            kiro_client = Client("Kiro IDE / CLI")
            policy = General("Admin policy\nmanaged-settings.json\n(Option B file)")
            aws_endpoints = Endpoint("AWS service endpoints\n(logs, kms, sts, s3)")
        egress = NATGateway("Allowlisted HTTPS egress\n(IdP sign-in, downloads, Kiro APIs)")
        with Cluster("Monitoring"):
            trail = Cloudtrail("CloudTrail")
            cw = Cloudwatch("CloudWatch")
            gd = Guardduty("GuardDuty")
            cfg = AwsConfig("AWS Config")
            kms = KMS("Customer-managed\nKMS keys")

    with Cluster(PROFILE_REGION):
        kiro = General("Kiro service\n(stores and processes\nprompts and code context)")
        prompt_logs = S3("Prompt logs and\nuser activity reports")

    idp >> Edge(label="OIDC + SCIM") >> kiro
    idp >> Edge(label="SAML 2.0") >> vdi
    directory >> Edge(label="WorkSpaces directory") >> vdi
    dev >> vdi >> kiro_client
    policy >> Edge(style="dashed", label="enforced by the Kiro client") >> kiro_client
    vdi >> aws_endpoints >> trail
    kiro_client >> egress >> Edge(label="HTTPS 443") >> kiro
    kiro >> prompt_logs

# --- Security Layers (this guide's 5-layer model, not a model defined by MAS) ---
with Diagram(
    "This Guide's 5-Layer Security Model",
    filename="security-layers",
    show=False,
    direction="TB",
    graph_attr=GRAPH_ATTR,
):
    dev = User("Banking developer")

    with Cluster("Layer 1: Identity - TRM 9.1, 9.2"):
        identity = Users("Enterprise IdP, MFA, SCIM\n(IAM Identity Center or\ndirect federation)")

    with Cluster("Layer 2: Network - TRM 11.2"):
        vpc = VPC("Private VPC,\nSGs and NACLs")
        aws_endpoints = Endpoint("AWS service\nendpoints")
        egress = NATGateway("Allowlisted\nHTTPS egress")

    with Cluster("Layer 3: Endpoint and VDI - TRM 9.3, 11.3, 11.4"):
        vdi = Workspaces("WorkSpaces VDI, DLP, GPO\n(no local admin rights)")

    with Cluster("Layer 4: Application and agent runtime - TRM 3.4, 6.1, 6.3"):
        runtime = Client("Kiro IDE / CLI\nadmin policy, permissions,\nhooks, MCP registry")

    with Cluster("Layer 5: Audit and monitoring - TRM 12.2, evidence for 15.1 IT audit"):
        prompt_logs = S3("Prompt logs and\nuser activity reports")
        trail = Cloudtrail("CloudTrail")
        cw = Cloudwatch("CloudWatch")
        gd = Guardduty("GuardDuty")
        hook_log = General("Hook audit log\n(shipped to the SIEM)")

    kiro = General("Kiro service\n(profile region)")

    dev >> identity >> vpc >> vdi >> runtime >> egress >> kiro
    vpc >> aws_endpoints
    runtime >> Edge(style="dashed", label="hook audit log") >> hook_log
    kiro >> Edge(style="dashed", label="prompt logs") >> prompt_logs
