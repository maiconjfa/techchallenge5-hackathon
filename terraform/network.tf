# -----------------------------------------------------------------------------
# VPC 10.0.0.0/16 com 4 subnets públicas em 2 AZs
# (2 subnets por AZ, alternando as AZs na ordem dos CIDRs)
# -----------------------------------------------------------------------------

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-vpc"
  })
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-igw"
  })
}

resource "aws_subnet" "public" {
  for_each = {
    for index, cidr in var.public_subnet_cidrs : tostring(index) => {
      cidr    = cidr
      az      = var.availability_zones[index % length(var.availability_zones)]
      ordinal = index + 1
    }
  }

  vpc_id                  = aws_vpc.main.id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.az
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = format("%s-public-%s-%d", var.name_prefix, each.value.az, each.value.ordinal)
    # Descoberta de subnets públicas pelo AWS Load Balancer Controller.
    "kubernetes.io/role/elb" = "1"
    # Permite que o EKS e o controller encontrem as subnets do cluster.
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
  })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-public-rt"
  })
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}
