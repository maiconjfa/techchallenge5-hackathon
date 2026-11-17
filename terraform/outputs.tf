# -----------------------------------------------------------------------------
# Identidade / rede
# -----------------------------------------------------------------------------

output "aws_account_id" {
  description = "Conta AWS usada pelo profile informado."
  value       = data.aws_caller_identity.current.account_id
}

output "aws_region" {
  description = "Região provisionada."
  value       = var.aws_region
}

output "vpc_id" {
  description = "ID da VPC."
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "IDs das 4 subnets públicas (ordem dos CIDRs informados)."
  value = [
    for index in range(length(var.public_subnet_cidrs)) :
    aws_subnet.public[tostring(index)].id
  ]
}

# -----------------------------------------------------------------------------
# EKS
# -----------------------------------------------------------------------------

output "eks_cluster_name" {
  description = "Nome do cluster EKS."
  value       = aws_eks_cluster.main.name
}

output "eks_cluster_endpoint" {
  description = "Endpoint da API do cluster."
  value       = aws_eks_cluster.main.endpoint
}

output "kubeconfig_command" {
  description = "Comando para configurar o kubectl no profile tf."
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${aws_eks_cluster.main.name} --profile ${var.aws_profile}"
}

output "oidc_provider_arn" {
  description = "ARN do OIDC provider usado pelo IRSA."
  value       = aws_iam_openid_connect_provider.eks.arn
}

output "irsa_role_arns" {
  description = "IAM Roles por ServiceAccount (use nas annotations dos overlays k8s)."
  value       = { for key, role in aws_iam_role.irsa : key => role.arn }
}

# -----------------------------------------------------------------------------
# ECR
# -----------------------------------------------------------------------------

output "ecr_repository_urls" {
  description = "URLs dos repositórios ECR (image.newName dos overlays k8s)."
  value       = { for key, repo in aws_ecr_repository.services : key => repo.repository_url }
}

# -----------------------------------------------------------------------------
# CI/CD (GitHub Actions)
# -----------------------------------------------------------------------------

output "github_actions_role_arn" {
  description = "ARN da role assumida pelo GitHub Actions via OIDC (secret AWS_ROLE_ARN)."
  value       = aws_iam_role.github_actions.arn
}

output "github_oidc_provider_arn" {
  description = "ARN do OIDC provider do GitHub usado pela role de CI/CD."
  value       = local.github_oidc_provider_arn
}

# -----------------------------------------------------------------------------
# Bancos relacionais
# -----------------------------------------------------------------------------

output "rds_endpoints" {
  description = "Endpoints host:porta de cada RDS."
  value       = { for key, db in aws_db_instance.main : key => "${db.address}:${db.port}" }
}

output "database_urls" {
  description = "DATABASE_URL completa de cada serviço (sensível)."
  value = {
    for key, db in aws_db_instance.main :
    key => "postgres://${db.username}:${random_password.db[key].result}@${db.address}:${db.port}/${db.db_name}"
  }
  sensitive = true
}

output "ngo_database_url" {
  description = "DATABASE_URL do ngo-service (sensível)."
  value       = "postgres://${aws_db_instance.main["ngo"].username}:${random_password.db["ngo"].result}@${aws_db_instance.main["ngo"].address}:${aws_db_instance.main["ngo"].port}/${aws_db_instance.main["ngo"].db_name}"
  sensitive   = true
}

output "donation_database_url" {
  description = "DATABASE_URL do donation-service (sensível)."
  value       = "postgres://${aws_db_instance.main["donation"].username}:${random_password.db["donation"].result}@${aws_db_instance.main["donation"].address}:${aws_db_instance.main["donation"].port}/${aws_db_instance.main["donation"].db_name}"
  sensitive   = true
}

# -----------------------------------------------------------------------------
# Mensageria / NoSQL
# -----------------------------------------------------------------------------

output "sqs_queue_url" {
  description = "URL da fila SQS de eventos de doação."
  value       = aws_sqs_queue.donations.url
}

output "sqs_queue_arn" {
  description = "ARN da fila SQS."
  value       = aws_sqs_queue.donations.arn
}

output "sqs_dlq_url" {
  description = "URL da dead-letter queue."
  value       = aws_sqs_queue.donations_dlq.url
}

output "dynamodb_table_name" {
  description = "Nome da tabela DynamoDB de voluntários."
  value       = aws_dynamodb_table.volunteers.name
}

output "dynamodb_table_arn" {
  description = "ARN da tabela DynamoDB."
  value       = aws_dynamodb_table.volunteers.arn
}

# -----------------------------------------------------------------------------
# FinOps
# -----------------------------------------------------------------------------

output "mandatory_tags" {
  description = "Tags obrigatórias aplicadas a todos os recursos taggable."
  value       = local.mandatory_tags
}
