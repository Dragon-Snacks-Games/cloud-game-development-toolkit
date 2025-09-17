# Fetch Steam SSFN config content from AWS Secrets Manager if provided
# The secret should contain the entire contents of config.vdf as the SecretString

data "aws_secretsmanager_secret_version" "steam_ssfn" {
  count     = var.steam_ssfn_secret_id != null ? 1 : 0
  secret_id = var.steam_ssfn_secret_id
}


# Resource to create a new (empty) Secrets Manager secret for Steam SSFN
# The secret's value must be manually set in AWS Secrets Manager after creation.
resource "aws_secretsmanager_secret" "steam_ssfn" {
  count       = var.create_steam_auth ? 1 : 0
  name        = local.steam_ssfn_secret_name
  description = "Steam SSFN data for TeamCity (value must be manually set after creation)"
  tags        = local.tags

  # Add lifecycle rule to prevent accidental deletion of a non-empty secret
  lifecycle {
    prevent_destroy = true
  }
}

