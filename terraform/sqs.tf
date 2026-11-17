# -----------------------------------------------------------------------------
# SQS: fila de eventos de doação + DLQ
# -----------------------------------------------------------------------------

resource "aws_sqs_queue" "donations_dlq" {
  name                      = "solidarytech-donations-dlq"
  message_retention_seconds = 1209600 # 14 dias
  sqs_managed_sse_enabled   = true

  tags = merge(local.common_tags, {
    Name    = "solidarytech-donations-dlq"
    Service = "donation-service"
    Purpose = "dead-letter-queue"
  })
}

resource "aws_sqs_queue" "donations" {
  name                       = "solidarytech-donations"
  visibility_timeout_seconds = 30
  message_retention_seconds  = 345600 # 4 dias
  receive_wait_time_seconds  = 20     # long polling
  sqs_managed_sse_enabled    = true

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.donations_dlq.arn
    maxReceiveCount     = 5
  })

  tags = merge(local.common_tags, {
    Name    = "solidarytech-donations"
    Service = "donation-service"
    Purpose = "donation-events"
  })
}
