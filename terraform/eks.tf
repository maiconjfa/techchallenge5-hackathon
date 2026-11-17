# -----------------------------------------------------------------------------
# EKS: control plane, OIDC (IRSA), managed node group e add-ons
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "eks" {
  name              = "/aws/eks/${local.cluster_name}/cluster"
  retention_in_days = var.cluster_log_retention_days

  tags = merge(local.common_tags, {
    Name = "${local.cluster_name}-logs"
  })
}

# -----------------------------------------------------------------------------
# IAM do control plane
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "eks_cluster_assume" {
  statement {
    sid     = "AllowEKSAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eks_cluster" {
  name               = "${var.name_prefix}-eks-cluster-role"
  assume_role_policy = data.aws_iam_policy_document.eks_cluster_assume.json

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-eks-cluster-role"
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSClusterPolicy"
}

# -----------------------------------------------------------------------------
# Cluster
# -----------------------------------------------------------------------------

resource "aws_eks_cluster" "main" {
  name     = local.cluster_name
  version  = var.cluster_version
  role_arn = aws_iam_role.eks_cluster.arn

  # Gerenciamos os add-ons via Terraform, então não deixamos o EKS
  # instalar as versões self-managed automaticamente.
  bootstrap_self_managed_addons = false

  vpc_config {
    subnet_ids              = [for subnet in aws_subnet.public : subnet.id]
    security_group_ids      = [aws_security_group.cluster.id]
    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs     = var.eks_public_access_cidrs
  }

  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }

  enabled_cluster_log_types = ["api", "audit", "authenticator"]

  depends_on = [
    aws_cloudwatch_log_group.eks,
    aws_iam_role_policy_attachment.eks_cluster,
    aws_route_table_association.public,
  ]

  tags = merge(local.common_tags, {
    Name = local.cluster_name
  })
}

# -----------------------------------------------------------------------------
# IAM dos nós
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "eks_nodes_assume" {
  statement {
    sid     = "AllowEC2AssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eks_nodes" {
  name               = "${var.name_prefix}-eks-nodes-role"
  assume_role_policy = data.aws_iam_policy_document.eks_nodes_assume.json

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-eks-nodes-role"
  })
}

resource "aws_iam_role_policy_attachment" "eks_nodes" {
  for_each = toset([
    "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore",
  ])

  role       = aws_iam_role.eks_nodes.name
  policy_arn = each.value
}

# -----------------------------------------------------------------------------
# Add-ons
# O VPC CNI é criado antes dos nós; CoreDNS e kube-proxy depois que há nós.
# -----------------------------------------------------------------------------

resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "vpc-cni"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"

  # Habilita as NetworkPolicies usadas em k8s/base/networkpolicy.yaml.
  configuration_values = jsonencode({
    enableNetworkPolicy = "true"
  })

  tags = merge(local.common_tags, {
    Name = "${local.cluster_name}-vpc-cni"
  })

  depends_on = [aws_eks_cluster.main]
}

resource "aws_eks_addon" "coredns" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "coredns"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"

  tags = merge(local.common_tags, {
    Name = "${local.cluster_name}-coredns"
  })

  depends_on = [aws_eks_node_group.main]
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "kube-proxy"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"

  tags = merge(local.common_tags, {
    Name = "${local.cluster_name}-kube-proxy"
  })

  depends_on = [aws_eks_node_group.main]
}

# -----------------------------------------------------------------------------
# Managed node group (subnets públicas + IP público, pois não há NAT Gateway)
# -----------------------------------------------------------------------------

resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.name_prefix}-nodes"
  node_role_arn   = aws_iam_role.eks_nodes.arn

  subnet_ids     = [for subnet in aws_subnet.public : subnet.id]
  instance_types = var.node_instance_types
  ami_type       = "AL2023_x86_64_STANDARD"
  capacity_type  = "ON_DEMAND"
  disk_size      = var.node_disk_size

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }

  update_config {
    max_unavailable = 1
  }

  labels = {
    role        = "general"
    environment = lower(var.environment)
  }

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-nodes"
  })

  depends_on = [
    aws_iam_role_policy_attachment.eks_nodes,
    aws_eks_addon.vpc_cni,
  ]
}
