# Fetch PlasticSCM credentials from AWS Secrets Manager
data "aws_secretsmanager_secret_version" "plastic_user" {
  secret_id = var.plastic_user_secret_id
}

# Local values for PlasticSCM environment variables
locals {
  plastic_secrets = [
    {
      name      = "PLASTIC_USER"
      valueFrom = "${data.aws_secretsmanager_secret_version.plastic_user.arn}:username::"
    },
    {
      name      = "PLASTIC_PASS"
      valueFrom = "${data.aws_secretsmanager_secret_version.plastic_user.arn}:password::"
    }
  ]

  plastic_env = [
    {
      name  = "PLASTIC_SERVER"
      value = var.plastic_server_url
    }
  ]
}