variable "aws_region" {
  description = "AWS region where the project will be deployed"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name prefix used for project resources"
  type        = string
  default     = "ironhack-voting"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "dev"
}

variable "instance_type" {
  description = "EC2 instance type for project servers"
  type        = string
  default     = "t3.micro"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets across two Availability Zones"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets across two Availability Zones"
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]
}
