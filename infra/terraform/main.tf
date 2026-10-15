data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  selected_azs = slice(data.aws_availability_zones.available.names, 0, 2)
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_vpc" "main" {

  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name        = "${var.project_name}-${var.environment}-vpc"
    Environment = var.environment
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-${var.environment}-igw"
  }
}

resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = local.selected_azs[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-${var.environment}-public-${count.index + 1}"
    Tier = "public"
  }
}


resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = local.selected_azs[count.index]

  tags = {
    Name = "${var.project_name}-${var.environment}-private-${count.index + 1}"
    Tier = "private"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  count  = 2
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-${var.environment}-private-rt-${count.index + 1}"
  }
}

resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}


# Security group for the public Application Load Balancer
resource "aws_security_group" "alb" {
  name        = "${var.project_name}-${var.environment}-alb-sg"
  description = "Allow web traffic to the Application Load Balancer"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP from the internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTPS will be enabled when a TLS certificate is configured.
  egress {
    description = "Allow outbound traffic to application targets"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-alb-sg"
  }
}

# Security group for the public Vote and Result application host
resource "aws_security_group" "app" {
  name        = "${var.project_name}-${var.environment}-app-sg"
  description = "Allow application traffic only from the ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Vote application host port"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description     = "Result application host port"
    from_port       = 8081
    to_port         = 8081
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description = "Allow outbound connections to internal services"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-app-sg"
  }
}

# Private EC2 host running Redis and the Worker
resource "aws_security_group" "backend" {
  name        = "${var.project_name}-${var.environment}-backend-sg"
  description = "Allow Redis access from application hosts"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Redis from application tier"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  egress {
    description = "Allow outbound connections to required services"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-backend-sg"
  }
}

# Private PostgreSQL hosts: primary and planned standby
resource "aws_security_group" "database" {
  name        = "${var.project_name}-${var.environment}-database-sg"
  description = "Restrict PostgreSQL access to application and backend tiers"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "PostgreSQL from Worker/backend tier"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.backend.id]
  }

  ingress {
    description     = "PostgreSQL reads from Result application"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  ingress {
    description = "PostgreSQL replication between database hosts"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    self        = true
  }

  egress {
    description = "Allow outbound database connections"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-database-sg"
  }
}


# Application Load Balancer
resource "aws_lb" "main" {
  name               = "${var.project_name}-${var.environment}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  tags = {
    Name        = "${var.project_name}-${var.environment}-alb"
    Environment = var.environment
  }
}

# Vote application target group
resource "aws_lb_target_group" "vote" {
  name        = "${var.project_name}-${var.environment}-vote"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "instance"

  health_check {
    enabled             = true
    protocol            = "HTTP"
    path                = "/"
    matcher             = "200"
    interval            = 30
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-vote-tg"
  }
}

# Result application target group
resource "aws_lb_target_group" "result" {
  name        = "${var.project_name}-${var.environment}-result"
  port        = 8081
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "instance"

  health_check {
    enabled             = true
    protocol            = "HTTP"
    path                = "/"
    matcher             = "200"
    interval            = 30
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-result-tg"
  }
}

# HTTP listener with path-based routing
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.vote.arn
  }
}

resource "aws_lb_listener_rule" "vote" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.vote.arn
  }

  condition {
    path_pattern {
      values = ["/vote", "/vote/*"]
    }
  }
}

resource "aws_lb_listener_rule" "result" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 200

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.result.arn
  }

  condition {
    path_pattern {
      values = ["/result", "/result/*"]
    }
  }
}

# IAM role assumed by EC2 instances
resource "aws_iam_role" "ec2" {
  name = "${var.project_name}-${var.environment}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = {
    Name = "${var.project_name}-${var.environment}-ec2-role"
  }
}

# Allow instances to be managed through AWS Systems Manager
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Instance profile attaches the IAM role to EC2
resource "aws_iam_instance_profile" "ec2" {
  name = "${var.project_name}-${var.environment}-ec2-profile"
  role = aws_iam_role.ec2.name
}


# Application server in Availability Zone 1
resource "aws_instance" "app_1" {
  ami                         = "ami-03714e87ed2cafc78"
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public[0].id
  vpc_security_group_ids      = [aws_security_group.app.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2.name
  associate_public_ip_address = true

  tags = {
    Name        = "${var.project_name}-${var.environment}-app-1"
    Role        = "application"
    Environment = var.environment
  }
}

# Application server in Availability Zone 2
resource "aws_instance" "app_2" {
  ami                         = "ami-03714e87ed2cafc78"
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public[1].id
  vpc_security_group_ids      = [aws_security_group.app.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2.name
  associate_public_ip_address = true

  tags = {
    Name        = "${var.project_name}-${var.environment}-app-2"
    Role        = "application"
    Environment = var.environment
  }
}

# Backend server in Availability Zone 1
resource "aws_instance" "backend_1" {
  ami                    = "ami-03714e87ed2cafc78"
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.private[0].id
  vpc_security_group_ids = [aws_security_group.backend.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2.name

  tags = {
    Name        = "${var.project_name}-${var.environment}-backend-1"
    Role        = "backend"
    Environment = var.environment
  }
}

# Backend server in Availability Zone 2
resource "aws_instance" "backend_2" {
  ami                    = "ami-03714e87ed2cafc78"
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.private[1].id
  vpc_security_group_ids = [aws_security_group.backend.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2.name

  tags = {
    Name        = "${var.project_name}-${var.environment}-backend-2"
    Role        = "backend"
    Environment = var.environment
  }
}

# Database server in Availability Zone 1
resource "aws_instance" "database_1" {
  ami                    = "ami-03714e87ed2cafc78"
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.private[0].id
  vpc_security_group_ids = [aws_security_group.database.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2.name

  tags = {
    Name        = "${var.project_name}-${var.environment}-database-1"
    Role        = "database"
    Environment = var.environment
  }
}

# Database server in Availability Zone 2
resource "aws_instance" "database_2" {
  ami                    = "ami-03714e87ed2cafc78"
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.private[1].id
  vpc_security_group_ids = [aws_security_group.database.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2.name

  tags = {
    Name        = "${var.project_name}-${var.environment}-database-2"
    Role        = "database"
    Environment = var.environment
  }
}


# Elastic IP for the NAT Gateway
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "${var.project_name}-${var.environment}-nat-eip"
  }
}

# NAT Gateway in the first public subnet
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id

  tags = {
    Name = "${var.project_name}-${var.environment}-nat"
  }

  depends_on = [aws_internet_gateway.main]
}

# Route private subnet 1 outbound traffic through the NAT Gateway
resource "aws_route" "private_nat_1" {
  route_table_id         = aws_route_table.private[0].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.main.id
}

# Route private subnet 2 outbound traffic through the NAT Gateway
resource "aws_route" "private_nat_2" {
  route_table_id         = aws_route_table.private[1].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.main.id
}


# Register both application EC2 instances with the Vote target group
resource "aws_lb_target_group_attachment" "vote_app_1" {
  target_group_arn = aws_lb_target_group.vote.arn
  target_id        = aws_instance.app_1.id
  port             = 8080
}

resource "aws_lb_target_group_attachment" "vote_app_2" {
  target_group_arn = aws_lb_target_group.vote.arn
  target_id        = aws_instance.app_2.id
  port             = 8080
}

# Register both application EC2 instances with the Result target group
resource "aws_lb_target_group_attachment" "result_app_1" {
  target_group_arn = aws_lb_target_group.result.arn
  target_id        = aws_instance.app_1.id
  port             = 8081
}

resource "aws_lb_target_group_attachment" "result_app_2" {
  target_group_arn = aws_lb_target_group.result.arn
  target_id        = aws_instance.app_2.id
  port             = 8081
}
