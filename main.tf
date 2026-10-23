terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# --- Variables ---

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "allowed_ip" {
  type        = string
  description = "Your personal IP address for secure SSH access (e.g., 198.51.100.1/32)"
  default     = "198.51.100.1/32"
}

variable "app_instance_profile_name" {
  type        = string
  description = "Optional name of an existing IAM instance profile to attach to application EC2 instances"
  default     = null
}

variable "docker_user" {
  type        = string
  description = "Docker Hub Username"
}

variable "docker_image_name" {
  type        = string
  description = "Repository name of the Docker image"
}

variable "docker_image_tag" {
  type        = string
  description = "The Jenkins build number used as the image tag"
}

variable "database_username" {
  type        = string
  description = "The database administrative user"
  default     = "root"
}

variable "database_password" {
  type        = string
  description = "The database administrative password"
  sensitive   = true
}

# --- Networking (VPC & Subnets) ---

resource "aws_vpc" "devsecops_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "devsecops-vpc"
    Environment = "Dev"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.devsecops_vpc.id

  tags = {
    Name = "devsecops-igw"
  }
}

resource "aws_subnet" "public_subnet_1" {
  vpc_id                  = aws_vpc.devsecops_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true

  tags = {
    Name = "devsecops-public-subnet-1"
  }
}

resource "aws_subnet" "public_subnet_2" {
  vpc_id                  = aws_vpc.devsecops_vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "${var.aws_region}b"
  map_public_ip_on_launch = true

  tags = {
    Name = "devsecops-public-subnet-2"
  }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.devsecops_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "devsecops-public-rt"
  }
}

resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public_subnet_1.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "public_assoc_2" {
  subnet_id      = aws_subnet.public_subnet_2.id
  route_table_id = aws_route_table.public_rt.id
}

# --- Security Groups ---

resource "aws_security_group" "alb_sg" {
  name        = "devsecops-alb-sg"
  description = "Allow public inbound HTTP traffic to the load balancer"
  vpc_id      = aws_vpc.devsecops_vpc.id

  ingress {
    description = "Allow public HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "devsecops-alb-sg"
  }
}

resource "aws_security_group" "app_sg" {
  name        = "devsecops-app-sg"
  description = "Allow restricted traffic from ALB and administrative SSH"
  vpc_id      = aws_vpc.devsecops_vpc.id

  ingress {
    description     = "Allow custom application container traffic from ALB only"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  ingress {
    description = "Allow administrative SSH from trusted network"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ip]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "devsecops-app-sg"
  }
}

# --- Load Balancing Infrastructure ---

resource "aws_lb" "app_alb" {
  name                       = "devsecops-app-alb"
  internal                   = false
  load_balancer_type         = "application"
  security_groups            = [aws_security_group.alb_sg.id]
  subnets                    = [aws_subnet.public_subnet_1.id, aws_subnet.public_subnet_2.id]
  drop_invalid_header_fields = true

  tags = {
    Name = "devsecops-app-alb"
  }
}

resource "aws_lb_target_group" "app_tg" {
  name        = "devsecops-app-tg"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = aws_vpc.devsecops_vpc.id
  target_type = "instance"

  health_check {
    enabled             = true
    path                = "/"
    port                = "8080"
    protocol            = "HTTP"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

resource "aws_lb_listener" "http_listener" {
  load_balancer_arn = aws_lb.app_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_tg.arn
  }
}

# --- Compute (AMI Data Source) ---

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

# --- Launch Template ---

resource "aws_launch_template" "app_lt" {
  name_prefix   = "devsecops-app-lt-"
  image_id      = data.aws_ami.ubuntu.id
  instance_type = "t3.micro"

  vpc_security_group_ids = [aws_security_group.app_sg.id]

  dynamic "iam_instance_profile" {
    for_each = var.app_instance_profile_name == null ? [] : [var.app_instance_profile_name]

    content {
      name = iam_instance_profile.value
    }
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 20
    encrypted             = true
    delete_on_termination = true
  }

  user_data = base64encode(<<-EOF
              #!/bin/bash
              apt-get update -y
              apt-get install -y docker.io curl git
              systemctl start docker
              systemctl enable docker

              docker network create devsecops-net

              docker run -d \
                --name mysql-db \
                --network devsecops-net \
                -e MYSQL_ROOT_PASSWORD=${var.database_password} \
                -e MYSQL_DATABASE=shopping_cart \
                mysql:8.0

              echo "Waiting for MySQL database startup..."
              until docker exec mysql-db mysqladmin ping -u root -p"${var.database_password}" --silent; do
                sleep 3
              done

              curl -sSL https://raw.githubusercontent.com/diehardrockstar-star/shoppingcart/master/databases/mysql_query.sql -o /tmp/schema.sql
              docker exec -i mysql-db mysql -u root -p"${var.database_password}" shopping_cart < /tmp/schema.sql

              docker run -d \
                --name web-app \
                --network devsecops-net \
                -p 8080:8080 \
                -e DB_USERNAME=${var.database_username} \
                -e DB_PASSWORD=${var.database_password} \
                ${var.docker_user}/${var.docker_image_name}:${var.docker_image_tag}
              EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name        = "devsecops-target-server"
      Environment = "Dev"
    }
  }
}

# --- Auto Scaling Group (Multi-AZ) ---

resource "aws_autoscaling_group" "app_asg" {
  name                = "devsecops-app-asg"
  desired_capacity    = 1
  min_size            = 1
  max_size            = 2
  target_group_arns   = [aws_lb_target_group.app_tg.arn]
  vpc_zone_identifier = [aws_subnet.public_subnet_1.id, aws_subnet.public_subnet_2.id]

  launch_template {
    id      = aws_launch_template.app_lt.id
    version = "$Latest"
  }

  health_check_type         = "ELB"
  health_check_grace_period = 300

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
    }
  }
}

# --- Outputs ---

output "vpc_id" {
  description = "The ID of the created VPC"
  value       = aws_vpc.devsecops_vpc.id
}

output "alb_dns_name" {
  description = "The public endpoint URL used to navigate to the application"
  value       = aws_lb.app_alb.dns_name
}
