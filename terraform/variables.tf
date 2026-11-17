variable "aws_region" {
  description = "Região AWS onde toda a infraestrutura será provisionada."
  type        = string
  default     = "us-east-1"

  validation {
    condition     = var.aws_region == "us-east-1"
    error_message = "O projeto está definido para us-east-1 (ALB, ACM e manifests Kubernetes assumem essa região)."
  }
}

variable "aws_profile" {
  description = "Profile do ~/.aws/config usado pelo provider AWS."
  type        = string
  default     = "tf"
}

variable "project" {
  description = "Tag obrigatória Project (FinOps)."
  type        = string
  default     = "SolidaryTech"

  validation {
    condition     = var.project == "SolidaryTech"
    error_message = "A política de tags exige Project=SolidaryTech."
  }
}

variable "environment" {
  description = "Tag obrigatória Environment (FinOps)."
  type        = string
  default     = "Production"

  validation {
    condition     = contains(["Development", "Staging", "Production"], var.environment)
    error_message = "Environment deve ser Development, Staging ou Production."
  }
}

variable "cost_center" {
  description = "Tag obrigatória CostCenter (FinOps)."
  type        = string
  default     = "NGO-Core"

  validation {
    condition     = can(regex("^[A-Za-z0-9._-]+$", var.cost_center))
    error_message = "CostCenter deve conter apenas letras, números, ponto, hífen ou underscore."
  }
}

variable "extra_tags" {
  description = "Tags adicionais (não podem sobrescrever as obrigatórias)."
  type        = map(string)
  default     = {}

  validation {
    condition = alltrue([
      for key in keys(var.extra_tags) :
      !contains(["Project", "Environment", "CostCenter"], key)
    ])
    error_message = "extra_tags não pode sobrescrever Project, Environment ou CostCenter."
  }
}

variable "name_prefix" {
  description = "Prefixo dos nomes dos recursos (minúsculo, sem espaços)."
  type        = string
  default     = "solidarytech-prod"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,30}$", var.name_prefix))
    error_message = "name_prefix deve começar com letra minúscula e ter 3-31 caracteres [a-z0-9-]."
  }
}

variable "vpc_cidr" {
  description = "CIDR da VPC."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = var.vpc_cidr == "10.0.0.0/16"
    error_message = "O projeto foi definido com VPC 10.0.0.0/16."
  }
}

variable "availability_zones" {
  description = "Duas AZs usadas pelas 4 subnets públicas."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]

  validation {
    condition     = length(var.availability_zones) == 2
    error_message = "Informe exatamente 2 availability zones."
  }
}

variable "public_subnet_cidrs" {
  description = "4 subnets públicas: 2 por AZ, alternando AZ conforme a ordem."
  type        = list(string)
  default     = ["10.0.0.0/20", "10.0.16.0/20", "10.0.32.0/20", "10.0.48.0/20"]

  validation {
    condition     = length(var.public_subnet_cidrs) == 4
    error_message = "Informe exatamente 4 CIDRs de subnets públicas."
  }
}

variable "cluster_version" {
  description = "Versão do Kubernetes no EKS."
  type        = string
  default     = "1.34"

  validation {
    condition     = can(regex("^1\\.(3[0-9])$", var.cluster_version))
    error_message = "Use uma versão EKS suportada no formato 1.xx."
  }
}

variable "cluster_log_retention_days" {
  description = "Retenção dos logs do control plane no CloudWatch (FinOps)."
  type        = number
  default     = 30
}

variable "eks_public_access_cidrs" {
  description = "CIDRs autorizados a acessar o endpoint público do EKS. Restrinja ao IP da equipe/CI."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "node_instance_types" {
  description = "Tipos de instância do managed node group."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_desired_size" {
  description = "Número inicial de nós."
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Número mínimo de nós."
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Número máximo de nós."
  type        = number
  default     = 4
}

variable "node_disk_size" {
  description = "Disco EBS (GiB) de cada nó."
  type        = number
  default     = 30
}

variable "db_instance_class" {
  description = "Classe das instâncias RDS (um banco por serviço)."
  type        = string
  default     = "db.t3.micro"
}

variable "db_allocated_storage" {
  description = "Storage inicial de cada RDS (GiB)."
  type        = number
  default     = 20
}

variable "db_max_allocated_storage" {
  description = "Teto do storage autoscaling de cada RDS (GiB). 0 desabilita."
  type        = number
  default     = 100
}

variable "db_backup_retention_period" {
  description = "Retenção de backups automáticos do RDS em dias."
  type        = number
  default     = 7
}

variable "db_multi_az" {
  description = "Multi-AZ do RDS (mais resiliente, maior custo)."
  type        = bool
  default     = false
}

variable "k8s_namespace" {
  description = "Namespace Kubernetes usado nas trust policies IRSA."
  type        = string
  default     = "solidarytech-prod"
}

# -----------------------------------------------------------------------------
# CI/CD (GitHub Actions via OIDC)
# -----------------------------------------------------------------------------

variable "github_repository" {
  description = "Repositório GitHub (owner/repo) autorizado a assumir a role de CI/CD."
  type        = string
  default     = "maiconjfa/techchallenge5-hackathon"

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repository))
    error_message = "github_repository deve estar no formato owner/repo."
  }
}

variable "github_branch" {
  description = "Branch autorizada na trust policy da role de CI/CD."
  type        = string
  default     = "main"

  validation {
    condition     = can(regex("^[A-Za-z0-9._/-]+$", var.github_branch))
    error_message = "github_branch deve conter apenas letras, números, ponto, hífen, underscore ou barra."
  }
}

variable "github_oidc_provider_arn" {
  description = "ARN de um OIDC provider do GitHub já existente. Vazio cria um novo provider."
  type        = string
  default     = ""

  validation {
    condition = var.github_oidc_provider_arn == "" || can(regex(
      "^arn:aws[a-z-]*:iam::[0-9]{12}:oidc-provider/token.actions.githubusercontent.com$",
      var.github_oidc_provider_arn
    ))
    error_message = "github_oidc_provider_arn deve ser vazio ou um ARN válido de oidc-provider do GitHub."
  }
}
