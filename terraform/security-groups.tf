# -----------------------------------------------------------------------------
# Security Groups
# - cluster: ENIs do control plane do EKS
# - nodes:   ENIs dos nos (pods usam os IPs dos nos via VPC CNI)
# - rds:     aceita 5432 apenas dos nos
# -----------------------------------------------------------------------------

resource "aws_security_group" "cluster" {
  name        = "${var.name_prefix}-eks-cluster"
  description = "Control plane do EKS ${local.cluster_name}"
  vpc_id      = aws_vpc.main.id

  egress {
    description = "Control plane para nos, ECR e APIs AWS"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-eks-cluster-sg"
  })
}

resource "aws_security_group" "nodes" {
  name        = "${var.name_prefix}-eks-nodes"
  description = "Nos do EKS ${local.cluster_name}"
  vpc_id      = aws_vpc.main.id

  egress {
    description = "Saida para internet, ECR, SQS, DynamoDB e RDS"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-eks-nodes-sg"
  })
}

# Nos -> control plane (HTTPS)
resource "aws_vpc_security_group_ingress_rule" "cluster_from_nodes" {
  security_group_id            = aws_security_group.cluster.id
  description                  = "Nos para o endpoint do control plane"
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  referenced_security_group_id = aws_security_group.nodes.id

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-cluster-ingress-nodes"
  })
}

# Control plane -> nos (kubelet 10250, NodePorts e webhooks)
resource "aws_vpc_security_group_ingress_rule" "nodes_from_cluster" {
  security_group_id            = aws_security_group.nodes.id
  description                  = "Control plane para kubelet e NodePorts"
  ip_protocol                  = "tcp"
  from_port                    = 1025
  to_port                      = 65535
  referenced_security_group_id = aws_security_group.cluster.id

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-nodes-ingress-cluster"
  })
}

# -----------------------------------------------------------------------------
# RDS: sem acesso público, apenas a partir dos nos do EKS
# -----------------------------------------------------------------------------

resource "aws_security_group" "rds" {
  name        = "${var.name_prefix}-rds"
  description = "PostgreSQL dos servicos SolidaryTech"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "PostgreSQL a partir dos nos do EKS"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.nodes.id]
  }

  egress {
    description = "Respostas para os clientes no VPC"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-rds-sg"
  })
}
