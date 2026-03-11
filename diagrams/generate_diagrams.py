"""
Generate architecture diagrams for Kiro Banking Best Practices.
Requires: pip install diagrams (and graphviz installed via brew/apt)
"""
from diagrams import Diagram, Cluster, Edge
from diagrams.aws.security import IAM, KMS
from diagrams.aws.network import VPC, Privatelink, Endpoint
from diagrams.aws.enduser import Workspaces
from diagrams.aws.management import Cloudtrail, Cloudwatch, Config as AwsConfig
from diagrams.aws.storage import S3
from diagrams.aws.general import User
from diagrams.onprem.security import Vault
from diagrams.onprem.client import Users

# --- Option A: Via IAM Identity Center ---
with Diagram(
    "Option A: Via AWS IAM Identity Center",
    filename="architecture-option-a",
    show=False,
    direction="TB",
    graph_attr={"fontsize": "14", "bgcolor": "white", "pad": "0.5"},
):
    idp = Users("Enterprise IdP\n(Entra ID / Okta)")
    idc = IAM("AWS IAM\nIdentity Center")

    with Cluster("Corporate VPC (Private Subnets Only)"):
        workspaces = Workspaces("Amazon WorkSpaces\n(VDI + DLP + GPO)")

        with Cluster("VPC Endpoints (Privatelink)"):
            kiro_ep = Endpoint("Kiro Endpoint")
            bedrock_ep = Endpoint("Bedrock Endpoint")
            logs_ep = Endpoint("CloudWatch Logs")

    with Cluster("Monitoring & Compliance"):
        trail = Cloudtrail("CloudTrail\nAudit Logs")
        cw = Cloudwatch("CloudWatch\nAlarms")
        cfg = AwsConfig("AWS Config\nCompliance Rules")
        bucket = S3("Audit Log\nBucket (KMS)")

    with Cluster("Encryption"):
        kms = KMS("Customer-Managed\nKMS Keys")

    idp >> Edge(label="SAML 2.0 + SCIM") >> idc
    idc >> Edge(label="Kiro subscription") >> kiro_ep
    idc >> Edge(label="VDI access") >> workspaces
    workspaces >> Edge(label="HTTPS/443") >> kiro_ep
    workspaces >> Edge(label="HTTPS/443") >> bedrock_ep
    trail >> bucket
    kms >> bucket
    trail >> logs_ep

# --- Option B: Direct IdP Federation ---
with Diagram(
    "Option B: Direct IdP Federation (No IAM IDC)",
    filename="architecture-option-b",
    show=False,
    direction="TB",
    graph_attr={"fontsize": "14", "bgcolor": "white", "pad": "0.5"},
):
    idp = Users("Enterprise IdP\n(Entra ID / Okta)")

    kiro_direct = Vault("Kiro IDE/CLI\n(OIDC + SCIM)")

    with Cluster("Corporate VPC (Private Subnets Only)"):
        workspaces = Workspaces("Amazon WorkSpaces\n(SAML 2.0 + VDI)")

        with Cluster("VPC Endpoints (Privatelink)"):
            kiro_ep = Endpoint("Kiro Endpoint")
            bedrock_ep = Endpoint("Bedrock Endpoint")
            logs_ep = Endpoint("CloudWatch Logs")

    with Cluster("Monitoring & Compliance"):
        trail = Cloudtrail("CloudTrail\nAudit Logs")
        cw = Cloudwatch("CloudWatch\nAlarms")
        cfg = AwsConfig("AWS Config\nCompliance Rules")
        bucket = S3("Audit Log\nBucket (KMS)")

    with Cluster("Encryption"):
        kms = KMS("Customer-Managed\nKMS Keys")

    idp >> Edge(label="OIDC + SCIM") >> kiro_direct
    idp >> Edge(label="SAML 2.0") >> workspaces
    workspaces >> Edge(label="HTTPS/443") >> kiro_ep
    workspaces >> Edge(label="HTTPS/443") >> bedrock_ep
    trail >> bucket
    kms >> bucket
    trail >> logs_ep

# --- Security Layers ---
with Diagram(
    "MAS TRM Security Layers",
    filename="security-layers",
    show=False,
    direction="TB",
    graph_attr={"fontsize": "14", "bgcolor": "white", "pad": "0.5"},
):
    user = User("Banking Developer")

    with Cluster("Layer 1: Identity (MAS TRM 9)"):
        idp = Users("Enterprise IdP\n+ MFA")

    with Cluster("Layer 2: Network (MAS TRM 11.2)"):
        vpc = VPC("Private VPC")
        pl = Privatelink("Privatelink\nEndpoints")

    with Cluster("Layer 3: Endpoint (MAS TRM 8.5)"):
        ws = Workspaces("WorkSpaces VDI\n+ DLP + GPO")

    with Cluster("Layer 4: Application"):
        kiro = Vault("Kiro IDE\n+ MCP Governance")

    with Cluster("Layer 5: Audit (MAS TRM 15)"):
        trail = Cloudtrail("CloudTrail")
        cw = Cloudwatch("CloudWatch")
        kms = KMS("KMS Encryption")

    user >> idp >> ws >> vpc >> pl >> kiro
    kiro >> trail
    trail >> kms
