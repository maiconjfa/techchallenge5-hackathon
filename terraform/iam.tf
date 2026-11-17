# -----------------------------------------------------------------------------
# OIDC provider do EKS (pré-requisito do IRSA)
# -----------------------------------------------------------------------------

data "tls_certificate" "eks" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]

  tags = merge(local.common_tags, {
    Name = "${local.cluster_name}-oidc"
  })
}

# -----------------------------------------------------------------------------
# IRSA: um IAM Role por ServiceAccount que acessa AWS
# (sem AWS_ACCESS_KEY_ID/SECRET no cluster)
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "irsa_assume" {
  for_each = local.irsa_roles

  statement {
    sid     = "AllowServiceAccountWebIdentity"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.eks.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer}:sub"
      values   = ["system:serviceaccount:${each.value.namespace}:${each.value.service_account}"]
    }
  }
}

resource "aws_iam_role" "irsa" {
  for_each = local.irsa_roles

  name               = "${var.name_prefix}-${each.key}"
  assume_role_policy = data.aws_iam_policy_document.irsa_assume[each.key].json

  tags = merge(local.common_tags, {
    Name    = "${var.name_prefix}-${each.key}"
    Service = each.key
  })
}

# -----------------------------------------------------------------------------
# donation-service -> SQS
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "donation_sqs" {
  statement {
    sid    = "SendDonationEvents"
    effect = "Allow"

    actions = [
      "sqs:SendMessage",
      "sqs:GetQueueUrl",
      "sqs:GetQueueAttributes",
    ]

    resources = [aws_sqs_queue.donations.arn]
  }
}

resource "aws_iam_policy" "donation_sqs" {
  name        = "${var.name_prefix}-donation-service-sqs"
  description = "Permite ao donation-service publicar eventos na fila SQS"
  policy      = data.aws_iam_policy_document.donation_sqs.json

  tags = merge(local.common_tags, {
    Name    = "${var.name_prefix}-donation-service-sqs"
    Service = "donation-service"
  })
}

resource "aws_iam_role_policy_attachment" "donation_sqs" {
  role       = aws_iam_role.irsa["donation-service"].name
  policy_arn = aws_iam_policy.donation_sqs.arn
}

# -----------------------------------------------------------------------------
# volunteer-service -> DynamoDB
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "volunteer_dynamodb" {
  statement {
    sid    = "VolunteersTableAccess"
    effect = "Allow"

    actions = [
      "dynamodb:PutItem",
      "dynamodb:GetItem",
      "dynamodb:Scan",
      "dynamodb:Query",
      "dynamodb:DescribeTable",
    ]

    resources = [aws_dynamodb_table.volunteers.arn]
  }
}

resource "aws_iam_policy" "volunteer_dynamodb" {
  name        = "${var.name_prefix}-volunteer-service-dynamodb"
  description = "Permite ao volunteer-service operar a tabela SolidaryTechVolunteers"
  policy      = data.aws_iam_policy_document.volunteer_dynamodb.json

  tags = merge(local.common_tags, {
    Name    = "${var.name_prefix}-volunteer-service-dynamodb"
    Service = "volunteer-service"
  })
}

resource "aws_iam_role_policy_attachment" "volunteer_dynamodb" {
  role       = aws_iam_role.irsa["volunteer-service"].name
  policy_arn = aws_iam_policy.volunteer_dynamodb.arn
}
