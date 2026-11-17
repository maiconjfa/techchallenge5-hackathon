provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile

  # Política de tags aplicada a todos os recursos taggable do provider.
  # Os recursos também declaram tags explicitamente via local.common_tags.
  default_tags {
    tags = local.common_tags
  }
}

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}
