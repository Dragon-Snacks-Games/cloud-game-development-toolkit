output "internal_alb_dns_name" {
  value       = aws_lb.teamcity_internal_lb.dns_name
  description = "DNS endpoint of the internal Application Load Balancer (ALB)"
}

output "external_alb_dns_name" {
  value       = aws_lb.teamcity_external_lb.dns_name
  description = "DNS endpoint of Application Load Balancer (ALB)"
}

output "external_alb_zone_id" {
  value       = aws_lb.teamcity_external_lb.zone_id
  description = "Zone ID for internet facing load balancer"
}

output "security_group_id" {
  value       = aws_security_group.teamcity_service_sg.id
  description = "The default security group of your Teamcity service."
}

output "teamcity_cluster_id" {
  value       = aws_ecs_cluster.teamcity_cluster[0].id
  description = "The ID of the ECS cluster"
}

output "plastic_env" {
  value = local.plastic_env
}

output "aws_connection_role_arn" {
  description = "The ARN of the IAM role for the TeamCity AWS connection."
  value       = var.create_aws_connection_role ? aws_iam_role.teamcity_aws_connection_role[0].arn : null
}