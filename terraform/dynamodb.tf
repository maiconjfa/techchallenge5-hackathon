# -----------------------------------------------------------------------------
# DynamoDB: tabela de voluntários (usada pelo volunteer-service)
# -----------------------------------------------------------------------------

resource "aws_dynamodb_table" "volunteers" {
  name         = "SolidaryTechVolunteers"
  billing_mode = "PAY_PER_REQUEST" # on-demand: FinOps para carga imprevisível
  hash_key     = "volunteer_id"

  attribute {
    name = "volunteer_id"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }

  # Hackathon: permite destroy. Em produção real, habilite a proteção.
  deletion_protection_enabled = false

  tags = merge(local.common_tags, {
    Name    = "SolidaryTechVolunteers"
    Service = "volunteer-service"
  })
}
