output "vpc_id" {
  description = "ID of the project VPC"
  value       = aws_vpc.main.id
}

output "availability_zones" {
  description = "Availability Zones used by this deployment"
  value       = local.selected_azs
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = aws_subnet.private[*].id
}


output "alb_dns_name" {
  description = "DNS name of the application load balancer"
  value       = aws_lb.main.dns_name
}

output "app_instance_ids" {
  description = "IDs of the application EC2 instances"
  value = [
    aws_instance.app_1.id,
    aws_instance.app_2.id
  ]
}

output "backend_instance_ids" {
  description = "IDs of the backend EC2 instances"
  value = [
    aws_instance.backend_1.id,
    aws_instance.backend_2.id
  ]
}

output "database_instance_ids" {
  description = "IDs of the database EC2 instances"
  value = [
    aws_instance.database_1.id,
    aws_instance.database_2.id
  ]
}
