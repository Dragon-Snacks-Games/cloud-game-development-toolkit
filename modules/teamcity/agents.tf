#################################
###### ECS TASK AND SERVICE #####
#################################

resource "aws_ecs_task_definition" "teamcity_agent" {
  # create a task for each build agent config in the build_farm_config variable
  #checkov:skip=CKV_AWS_336: EFS is not necessary for TeamCity Agents

  for_each = var.build_farm_config

  family                   = each.key
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = each.value.cpu
  memory                   = each.value.memory
  execution_role_arn       = aws_iam_role.teamcity_agent_task_execution_role.arn
  task_role_arn            = aws_iam_role.teamcity_agent_default_role.arn
  container_definitions = jsonencode([
    merge({
      name      = "teamcity-agent"
      image     = each.value.image
      cpu       = each.value.cpu
      memory    = each.value.memory
      essential = true
      environment = concat([
        {
          name  = "SERVER_URL"
          value = "http://teamcity-server.teamcity-namespace:8111"
        },
        {
          name  = "AGENT_NAME"
          value = "${each.key}-agent"
        }
      ], local.plastic_env)
      secrets = concat(local.plastic_secrets, local.steam_secrets)
    }, var.enable_agent_cloudwatch_logs ? {
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.teamcity_agent.name
          "awslogs-region"        = data.aws_region.current.name
          "awslogs-stream-prefix" = "[AGENT - ${each.key}]"
        }
      }
    } : {})
  ])
}

resource "aws_ecs_service" "teamcity_agent" {
  for_each = var.build_farm_config

  name = each.key
  cluster = (var.cluster_name != null ? data.aws_ecs_cluster.teamcity_cluster[0].arn :
  aws_ecs_cluster.teamcity_cluster[0].arn)
  task_definition = aws_ecs_task_definition.teamcity_agent[each.key].arn
  desired_count   = each.value.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = var.service_subnets
    security_groups = [aws_security_group.teamcity_agent_sg.id]
  }

  enable_execute_command = var.debug

  service_connect_configuration {
    enabled   = true
    namespace = aws_service_discovery_http_namespace.teamcity[0].arn

    dynamic "log_configuration" {
      for_each = var.enable_agent_cloudwatch_logs ? [1] : []
      content {
        log_driver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.teamcity_agent.name
          "awslogs-region"        = data.aws_region.current.name
          "awslogs-stream-prefix" = "[AGENT - ${each.key}]"
        }
      }
    }
  }

  depends_on = [
    aws_ecs_service.teamcity
  ]
}

#################################
### SECURITY GROUPS FOR AGENTS ##
#################################

# SECURITY GROUP FOR TEAMCITY AGENTS
resource "aws_security_group" "teamcity_agent_sg" {
  name        = "teamcity_agent_sg"
  description = "Security Group for Teamcity Agents"
  vpc_id      = var.vpc_id
}

# SECURITY GROUP EGRESS FOR TEAMCITY AGENTS
resource "aws_vpc_security_group_egress_rule" "teamcity_agent_outbound" {
  security_group_id = aws_security_group.teamcity_agent_sg.id
  description       = "Allow outbound to anywhere"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# SECURITY GROUP FOR TEAMCITY SERVICE TO ALLOW TEAMCITY AGENT
resource "aws_vpc_security_group_ingress_rule" "teamcity_agent_inbound" {
  security_group_id            = aws_security_group.teamcity_service_sg.id
  description                  = "Allow inbound traffic from Teamcity Agent"
  referenced_security_group_id = aws_security_group.teamcity_agent_sg.id
  from_port                    = var.container_port
  to_port                      = var.container_port
  ip_protocol                  = "TCP"
}

# SECURITY GROUP FOR TEAMCITY AGENT TO ALLOW TEAMCITY SERVICE
resource "aws_vpc_security_group_ingress_rule" "teamcity_service_inbound_to_agent" {
  security_group_id            = aws_security_group.teamcity_agent_sg.id
  description                  = "Allow inbound traffic from Teamcity Service"
  referenced_security_group_id = aws_security_group.teamcity_service_sg.id
  from_port                    = -1 # Allow all ports for ephemeral responses
  to_port                      = -1
  ip_protocol                  = "-1" # Allow all protocols
}

# SECURITY GROUP EGRESS FOR TEAMCITY SERVICE TO TEAMCITY AGENT
resource "aws_vpc_security_group_egress_rule" "teamcity_service_outbound_to_agent" {
  security_group_id            = aws_security_group.teamcity_service_sg.id
  description                  = "Allow outbound traffic to Teamcity Agent"
  referenced_security_group_id = aws_security_group.teamcity_agent_sg.id
  from_port                    = -1 # Allow all ports
  to_port                      = -1
  ip_protocol                  = "-1" # Allow all protocols
}

#################################
#### IAM ROLES AND POLICIES #####
#################################

data "aws_iam_policy_document" "teamcity_agent_default_policy" {
  #checkov:skip=CKV_AWS_111: resources need IAM write permissions
  #checkov:skip=CKV_AWS_356: resources need IAM write permissions
  statement {
    sid    = "ECSExec"
    effect = "Allow"
    actions = [
      "ssmmessages:OpenDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:CreateControlChannel",
    ]
    resources = [
      "*"
    ]
  }

  statement {
    sid       = "ServiceDiscovery"
    effect    = "Allow"
    actions   = ["servicediscovery:DiscoverInstances"]
    resources = ["*"]
  }

  statement {
    sid       = "logs"
    effect    = "Allow"
    actions   = ["logs:CreateLogGroup"]
    resources = ["*"]
  }
}


resource "aws_iam_policy" "teamcity_agent_default_policy" {
  name        = "teamcity-agent-default-policy"
  description = "Default policy for Teamcity Agents permissions"
  policy      = data.aws_iam_policy_document.teamcity_agent_default_policy.json
}

resource "aws_iam_role" "teamcity_agent_default_role" {
  name               = "teamcity-agent-default-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_trust_relationship.json

}

resource "aws_iam_role_policy_attachment" "teamcity_agent_default_role_policy_attachment" {
  role       = aws_iam_role.teamcity_agent_default_role.name
  policy_arn = aws_iam_policy.teamcity_agent_default_policy.arn
}

# Plastic secrets access for agents (optional)
data "aws_iam_policy_document" "teamcity_agent_execution_plastic_policy" {
  count = var.plastic_user_secret_id != null ? 1 : 0
  statement {
    sid    = "SecretsManagerPlastic"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret"
    ]
    resources = [
      data.aws_secretsmanager_secret_version.plastic_user.arn
    ]
  }
}

resource "aws_iam_policy" "teamcity_agent_execution_plastic_policy" {
  count  = var.plastic_user_secret_id != null ? 1 : 0
  name   = "teamcity-agent-execution-plastic-policy"
  policy = data.aws_iam_policy_document.teamcity_agent_execution_plastic_policy[0].json
}

# Steam SSFN secret access for agents (optional)
data "aws_iam_policy_document" "teamcity_agent_execution_steam_policy" {
  count = local.steam_ssfn_secret_arn != null ? 1 : 0
  statement {
    sid    = "SecretsManagerSteam"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret"
    ]
    resources = [
      local.steam_ssfn_secret_arn
    ]
  }
}

resource "aws_iam_policy" "teamcity_agent_execution_steam_policy" {
  count  = local.steam_ssfn_secret_arn != null ? 1 : 0
  name   = "teamcity-agent-execution-steam-policy"
  policy = data.aws_iam_policy_document.teamcity_agent_execution_steam_policy[0].json
}


resource "aws_iam_role" "teamcity_agent_task_execution_role" {
  name               = "teamcity-agent-task-execution-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_trust_relationship.json
}

resource "aws_iam_role_policy_attachment" "teamcity_agent_task_execution_default_policy" {
  #checkov:skip=CKV_AWS_338: does not need CW logs for a year
  #checkov:skip=CKV_AWS_158: CW Log Group does not need to be encrypted
  role       = aws_iam_role.teamcity_agent_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy_attachment" "teamcity_agent_task_execution_plastic_secrets_policy" {
  count      = var.plastic_user_secret_id != null ? 1 : 0
  role       = aws_iam_role.teamcity_agent_task_execution_role.name
  policy_arn = aws_iam_policy.teamcity_agent_execution_plastic_policy[0].arn
}

resource "aws_iam_role_policy_attachment" "teamcity_agent_task_execution_steam_secrets_policy" {
  count      = local.steam_ssfn_secret_arn != null ? 1 : 0
  role       = aws_iam_role.teamcity_agent_task_execution_role.name
  policy_arn = aws_iam_policy.teamcity_agent_execution_steam_policy[0].arn
}

resource "aws_cloudwatch_log_group" "teamcity_agent" {
  #checkov:skip=CKV_AWS_158: CW Log Group does not need to be encrypted
  #checkov:skip=CKV_AWS_338: CW Log Group does not need to be retained for 1 year
  name              = "/ecs/teamcity-agent"
  retention_in_days = var.agent_log_group_retention_in_days
}
