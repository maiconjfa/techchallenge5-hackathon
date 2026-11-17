# Regras do TFLint usadas no pipeline .github/workflows/infra-ci.yml
# TFLint e opcional localmente: `tflint --init && tflint`

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

plugin "aws" {
  enabled = true
  version = "0.50.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}
