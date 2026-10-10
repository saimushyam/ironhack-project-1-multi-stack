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
