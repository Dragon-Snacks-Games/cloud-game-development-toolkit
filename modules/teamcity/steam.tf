# Fetch Steam SSFN config content from AWS Secrets Manager if provided
# The secret should contain the entire contents of config.vdf as the SecretString

data "aws_secretsmanager_secret_version" "steam_ssfn" {
  count     = var.steam_ssfn_secret_id != null ? 1 : 0
  secret_id = var.steam_ssfn_secret_id
}

# Local values to inject the secret into ECS tasks as an environment variable
locals {
  steam_secrets = var.steam_ssfn_secret_id != null ? [
    {
      name      = "STEAM_SSFN_CONTENT"
      # When the secret contains the entire config.vdf in SecretString, no JSON key suffix is required
      valueFrom = data.aws_secretsmanager_secret_version.steam_ssfn[0].arn
    }
  ] : []
}
