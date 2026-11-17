locals {
  # ---------------------------------------------------------------------------
  # Política de tags FinOps (obrigatória em todos os recursos)
  # ---------------------------------------------------------------------------
  mandatory_tags = {
    Project     = var.project
    Environment = var.environment
    CostCenter  = var.cost_center
  }

  common_tags = merge(
    local.mandatory_tags,
    {
      ManagedBy = "Terraform"
    },
    var.extra_tags,
  )

  # ---------------------------------------------------------------------------
  # Nomes
  # ---------------------------------------------------------------------------
  cluster_name = "${var.name_prefix}-eks"

  # ---------------------------------------------------------------------------
  # Catálogo de bancos: um RDS PostgreSQL por serviço relacional
  # ---------------------------------------------------------------------------
  databases = {
    ngo = {
      identifier  = "${var.name_prefix}-ngo-db"
      db_name     = "ngo_db"
      service     = "ngo-service"
      description = "PostgreSQL do ngo-service"
    }
    donation = {
      identifier  = "${var.name_prefix}-donation-db"
      db_name     = "donation_db"
      service     = "donation-service"
      description = "PostgreSQL do donation-service"
    }
  }

  # Repositórios ECR usados pelos manifests (k8s/overlays/*/kustomization.yaml).
  ecr_repositories = ["ngo-service", "donation-service", "volunteer-service"]

  # ServiceAccounts que recebem IAM Role via IRSA.
  # Os nomes precisam casar com os overlays Kubernetes:
  #   solidarytech-prod-donation-service / solidarytech-prod-volunteer-service
  irsa_roles = {
    donation-service = {
      namespace       = var.k8s_namespace
      service_account = "donation-service"
    }
    volunteer-service = {
      namespace       = var.k8s_namespace
      service_account = "volunteer-service"
    }
  }

  oidc_issuer = replace(aws_eks_cluster.main.identity[0].oidc[0].issuer, "https://", "")

  # OIDC do GitHub: usa um provider existente ou o criado em github-oidc.tf.
  github_oidc_provider_arn = (
    var.github_oidc_provider_arn != ""
    ? var.github_oidc_provider_arn
    : aws_iam_openid_connect_provider.github[0].arn
  )
}
