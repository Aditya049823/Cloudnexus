
terraform {
  required_version = ">= 1.5.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = "ap-south-1"
}


resource "aws_s3_bucket" "app_storage" {
  bucket = "${var.project_name}-${var.environment}-aditya-lab-storage"

  tags = {
    Name        = "${var.project_name}-${var.environment}-storage"
    Environment = var.environment
    Project     = var.project_name
  }
}


resource "aws_vpc" "cloudnexus" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name        = "cloudnexus-vpc"
    Project     = "cloudnexus"
    Environment = var.environment
  }
}


resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.cloudnexus.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "ap-south-1a"
  map_public_ip_on_launch = true

  tags = {
    Name        = "cloudnexus-public-a"
    Project     = var.project_name
    Environment = var.environment
    Tier        = "public"
  }
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.cloudnexus.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "ap-south-1b"
  map_public_ip_on_launch = true

  tags = {
    Name        = "cloudnexus-public-b"
    Project     = var.project_name
    Environment = var.environment
    Tier        = "public"
  }
}


resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.cloudnexus.id
  cidr_block        = "10.0.11.0/24"
  availability_zone = "ap-south-1a"

  tags = {
    Name        = "cloudnexus-private-a"
    Project     = var.project_name
    Environment = var.environment
    Tier        = "private"
  }
}

resource "aws_subnet" "private_b" {
  vpc_id            = aws_vpc.cloudnexus.id
  cidr_block        = "10.0.12.0/24"
  availability_zone = "ap-south-1b"

  tags = {
    Name        = "cloudnexus-private-b"
    Project     = var.project_name
    Environment = var.environment
    Tier        = "private"
  }
}


resource "aws_internet_gateway" "cloudnexus" {
  vpc_id = aws_vpc.cloudnexus.id

  tags = {
    Name        = "cloudnexus-igw"
    Project     = var.project_name
    Environment = var.environment
  }
}


resource "aws_route_table" "public" {
  vpc_id = aws_vpc.cloudnexus.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.cloudnexus.id
  }

  tags = {
    Name        = "cloudnexus-public-rt"
    Project     = var.project_name
    Environment = var.environment
  }
}


resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}


resource "aws_route_table" "private" {
  vpc_id = aws_vpc.cloudnexus.id

  tags = {
    Name        = "cloudnexus-private-rt"
    Project     = var.project_name
    Environment = var.environment
  }
}


resource "aws_route_table_association" "private_a" {
  subnet_id      = aws_subnet.private_a.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_b" {
  subnet_id      = aws_subnet.private_b.id
  route_table_id = aws_route_table.private.id
}


resource "aws_security_group" "alb" {
  name        = "cloudnexus-alb-sg"
  description = "Security group for the CloudNexus load balancer"
  vpc_id      = aws_vpc.cloudnexus.id

  tags = {
    Name        = "cloudnexus-alb-sg"
    Project     = var.project_name
    Environment = var.environment
  }
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  description       = "Allow HTTP traffic to the application load balancer"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "alb_egress" {
  security_group_id = aws_security_group.alb.id
  description       = "Allow outbound traffic from the load balancer"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}


resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name        = "cloudnexus-nat-eip"
    Project     = var.project_name
    Environment = var.environment
  }
}


resource "aws_nat_gateway" "cloudnexus" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_a.id

  tags = {
    Name        = "cloudnexus-nat"
    Project     = var.project_name
    Environment = var.environment
  }

  depends_on = [
    aws_internet_gateway.cloudnexus
  ]
}


resource "aws_route" "private_internet" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.cloudnexus.id
}


resource "aws_iam_role" "eks_cluster" {
  name = "cloudnexus-eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "eks.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = {
    Project     = var.project_name
    Environment = var.environment
  }
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}


# IAM role for EKS worker nodes (EC2 instances)
resource "aws_iam_role" "eks_node" {
  name = "cloudnexus-eks-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "cloudnexus-eks-node-role"
    Project     = var.project_name
    Environment = var.environment
  }
}

# Allows worker nodes to communicate with the EKS control plane
resource "aws_iam_role_policy_attachment" "eks_worker_node" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

# Allows the Amazon VPC CNI plugin to manage pod networking
resource "aws_iam_role_policy_attachment" "eks_cni" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

# Allows worker nodes to pull container images from Amazon ECR
resource "aws_iam_role_policy_attachment" "eks_ecr_readonly" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}


resource "aws_eks_cluster" "cloudnexus" {
  name     = "${var.project_name}-${var.environment}-eks"
  role_arn = aws_iam_role.eks_cluster.arn
  version  = "1.37"

  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }

  vpc_config {
    subnet_ids = [
      aws_subnet.private_a.id,
      aws_subnet.private_b.id
    ]

    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs     = ["103.186.246.196/32"]
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-eks"
    Project     = var.project_name
    Environment = var.environment
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy
  ]
}


resource "aws_eks_node_group" "cloudnexus" {
  cluster_name    = aws_eks_cluster.cloudnexus.name
  node_group_name = "${var.project_name}-${var.environment}-nodes"
  node_role_arn   = aws_iam_role.eks_node.arn

  subnet_ids = [
    aws_subnet.private_a.id,
    aws_subnet.private_b.id
  ]

  instance_types = ["t3.small"]
  capacity_type  = "ON_DEMAND"

  scaling_config {
    desired_size = 1
    min_size     = 1
    max_size     = 2
  }

  update_config {
    max_unavailable = 1
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-nodes"
    Project     = var.project_name
    Environment = var.environment
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node,
    aws_iam_role_policy_attachment.eks_cni,
    aws_iam_role_policy_attachment.eks_ecr_readonly
  ]
}


resource "aws_ecr_repository" "cloudnexus_web" {
  name                 = "${var.project_name}-${var.environment}-web"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-web"
    Project     = var.project_name
    Environment = var.environment
  }
}
