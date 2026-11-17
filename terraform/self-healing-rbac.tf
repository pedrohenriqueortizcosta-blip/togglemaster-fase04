# ---------------------------------------------------------------------------
# Requirement 4 self-healing: lets the GitHub Actions OIDC role (already
# used by every CI pipeline for ECR push — see modules/github-oidc) also
# run `kubectl rollout restart` against auth-service specifically, the one
# service our demo alert/self-healing targets.
#
# This cluster's EKS authentication mode is CONFIG_MAP only (confirmed via
# `aws eks list-access-entries` erroring out, which only works on
# API/API_AND_CONFIG_MAP clusters) — so the only way to grant a role
# cluster access is the classic aws-auth ConfigMap, not the newer EKS
# Access Entries API.
#
# kubernetes_config_map_v1_data (not kubernetes_config_map) does a
# server-side-apply PATCH rather than owning/replacing the whole object —
# critical here, since aws-auth already has the node role's mapRoles entry
# (seeded automatically by EKS at node-group creation, never Terraform-
# managed) that this must not clobber.
# ---------------------------------------------------------------------------

# Real bug found during Requirement 4 testing: `aws eks update-kubeconfig`
# needs this AWS IAM-level permission just to fetch the cluster's endpoint/
# CA cert, BEFORE kubectl ever gets to use the Kubernetes RBAC granted
# below -- a separate layer entirely from the in-cluster Role/RoleBinding.
# First self-healing run failed on exactly this ("AccessDeniedException ...
# eks:DescribeCluster ... no identity-based policy allows").
data "aws_caller_identity" "current" {}

resource "aws_iam_role_policy" "github_actions_eks_describe" {
  name = "${split("/", module.github_oidc.role_arn)[1]}-eks-describe"
  role = split("/", module.github_oidc.role_arn)[1]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "EKSDescribe"
        Effect   = "Allow"
        Action   = ["eks:DescribeCluster"]
        Resource = "arn:aws:eks:us-east-1:${data.aws_caller_identity.current.account_id}:cluster/${module.eks.cluster_name}"
      }
    ]
  })
}

resource "kubernetes_role" "self_healing_dispatcher" {
  metadata {
    name      = "self-healing-dispatcher"
    namespace = kubernetes_namespace.services["auth-service"].metadata[0].name
  }

  rule {
    api_groups = ["apps"]
    resources  = ["deployments"]
    # "patch" is what `kubectl rollout restart` actually does under the
    # hood (it patches the pod template's restart annotation); get/list
    # let it resolve/verify the deployment first.
    verbs = ["get", "list", "patch"]
  }
}

resource "kubernetes_role_binding" "self_healing_dispatcher" {
  metadata {
    name      = "self-healing-dispatcher"
    namespace = kubernetes_namespace.services["auth-service"].metadata[0].name
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.self_healing_dispatcher.metadata[0].name
  }

  subject {
    kind      = "Group"
    name      = "self-healing-operators"
    api_group = "rbac.authorization.k8s.io"
  }
}

resource "kubernetes_config_map_v1_data" "aws_auth_self_healing" {
  # "mapRoles" is a single opaque YAML-encoded STRING value, not something
  # Kubernetes/SSA can merge piecewise — field-manager ownership works per
  # top-level ConfigMap key, not per list-item inside that key's string
  # content. So this must re-state the FULL desired list (the existing
  # node role entry, seeded automatically by EKS at node-group creation
  # and never otherwise Terraform-managed, PLUS the new self-healing
  # entry) in one go, or the node role mapping would be silently wiped —
  # breaking node bootstrapping entirely. force=false still makes this
  # fail loudly instead of silently overwriting, if that node role entry
  # ever changes shape outside this file.
  #
  # Actually needed: the real owner of this field is EKS's own bootstrap
  # controller ("Kubernetes Java Client" field manager), not Terraform —
  # confirmed via the "Field manager conflict" error on the first apply
  # attempt with force=false. Verified via `terraform plan` beforehand
  # that this resource's content exactly preserves that existing entry
  # (same rolearn/username/groups) before setting force=true to take over
  # ownership going forward.
  force = true

  metadata {
    name      = "aws-auth"
    namespace = "kube-system"
  }

  data = {
    mapRoles = yamlencode([
      {
        rolearn  = module.eks.node_role_arn
        username = "system:node:{{EC2PrivateDNSName}}"
        groups   = ["system:bootstrappers", "system:nodes"]
      },
      {
        rolearn  = module.github_oidc.role_arn
        username = "self-healing-dispatcher"
        groups   = ["self-healing-operators"]
      }
    ])
  }
}
