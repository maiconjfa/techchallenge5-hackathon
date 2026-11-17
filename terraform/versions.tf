terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

  # Backend remoto recomendado para uso em equipe/CI.
  # 1. Crie o bucket S3 versionado/criptografado e a tabela de lock.
  # 2. Copie backend.tf.example para backend.tf e preencha os valores.
  # 3. Execute: terraform init -migrate-state
  #
  # backend "s3" {}
}
