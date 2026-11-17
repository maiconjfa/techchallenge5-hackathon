# -----------------------------------------------------------------------------
# RDS PostgreSQL: um banco por serviço relacional
#   ngo-service      -> ngo_db
#   donation-service -> donation_db
# volunteer-service usa DynamoDB e não tem RDS.
# -----------------------------------------------------------------------------

data "aws_rds_engine_version" "postgres" {
  engine                 = "postgres"
  parameter_group_family = "postgres16"
  latest                 = true
}

resource "random_password" "db" {
  for_each = local.databases

  length  = 32
  special = false # evita problemas de encoding dentro da DATABASE_URL
}

resource "aws_db_subnet_group" "main" {
  name       = "${var.name_prefix}-rds"
  subnet_ids = [for subnet in aws_subnet.public : subnet.id]

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-rds-subnet-group"
  })
}

resource "aws_db_instance" "main" {
  for_each = local.databases

  identifier = each.value.identifier

  engine         = "postgres"
  engine_version = data.aws_rds_engine_version.postgres.version
  instance_class = var.db_instance_class

  allocated_storage     = var.db_allocated_storage
  max_allocated_storage = var.db_max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = each.value.db_name
  username = "solidary_user"
  password = random_password.db[each.key].result

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false

  multi_az                = var.db_multi_az
  backup_retention_period = var.db_backup_retention_period
  backup_window           = "03:00-04:00"
  maintenance_window      = "sun:04:00-sun:05:00"

  auto_minor_version_upgrade = true
  copy_tags_to_snapshot      = true
  apply_immediately          = false

  # Ambiente de hackathon: permite destroy sem snapshot final.
  # Em produção real, use deletion_protection = true e skip_final_snapshot = false.
  skip_final_snapshot = true
  deletion_protection = false

  performance_insights_enabled = false

  tags = merge(local.common_tags, {
    Name    = each.value.identifier
    Service = each.value.service
  })
}
