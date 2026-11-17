# -----------------------------------------------------------------------------
# GitHub Actions OIDC -> AWS (CI/CD sem chaves estaticas)
#
# Cria o OIDC provider do GitHub (ou reutiliza um existente via
# var.github_oidc_provider_arn) e uma role com permissao de push no ECR.
#
# A trust policy aceita apenas a branch configurada em var.github_branch do
# repositorio var.github_repository. O ARN da role e exposto no output
# github_actions_role_arn e deve ser salvo no secret AWS_ROLE_ARN do GitHub.
# -----------------------------------------------------------------------------

resource "aws_iam_openid_connect_provider" "github" {
  count = var.github_oidc_provider_arn == "" ? 1 : 0

  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1", "1c58a3a8518e8759bf075b76b750d4f2df264fcd"]

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-github-oidc"
  })
}

data "aws_iam_policy_document" "github_actions_assume" {
  statement {
    sid     = "AllowGitHubActionsOIDC"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.github_oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repository}:ref:refs/heads/${var.github_branch}"]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  name                 = "${var.name_prefix}-github-actions"
  description          = "Role do GitHub Actions para push de imagens no ECR (OIDC)"
  assume_role_policy   = data.aws_iam_policy_document.github_actions_assume.json
  max_session_duration = 3600

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-github-actions"
  })
}

data "aws_iam_policy_document" "github_actions_ecr" {
  statement {
    sid    = "EcrGetAuthorizationToken"
    effect = "Allow"

    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid    = "EcrPushPullServiceImages"
    effect = "Allow"

    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeImages",
      "ecr:DescribeRepositories",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:ListImages",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
    ]

    resources = [for repo in aws_ecr_repository.services : repo.arn]
  }
}

resource "aws_iam_policy" "github_actions_ecr" {
  name        = "${var.name_prefix}-github-actions-ecr"
  description = "Permite ao GitHub Actions publicar imagens nos repositorios ECR do projeto"
  policy      = data.aws_iam_policy_document.github_actions_ecr.json

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-github-actions-ecr"
  })
}

resource "aws_iam_role_policy_attachment" "github_actions_ecr" {
  role       = aws_iam_role.github_actions.name
  policy_arn = aws_iam_policy.github_actions_ecr.arn
}
