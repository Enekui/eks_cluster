resource "aws_vpc" "eks_vpc" {
  cidr_block       = var.vpc["cidr_block"]
  instance_tenancy = var.vpc["instance_tenancy"]
  enable_dns_support = true
  enable_dns_hostnames = true

  tags = {
    Name = var.vpc["name"]
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}

resource "aws_key_pair" "macbook_pro" {
  key_name   = "macbook_pro"
  public_key = file("~/.ssh/id_rsa.pub")
}

resource "aws_subnet" "eks_subnet" {
  count = length(var.subnet)
  vpc_id     = aws_vpc.eks_vpc.id
  cidr_block = var.subnet[count.index]["cidr_block"]
  availability_zone = var.subnet[count.index]["availability_zone"]
  map_public_ip_on_launch = true

  tags = {
    Name = var.subnet[count.index]["name"]
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}

resource "aws_internet_gateway" "eks_gateway" {
  vpc_id = aws_vpc.eks_vpc.id

  tags = {
    Name = "eks_gateway"
  }
}

resource "aws_route_table" "eks_route_table" {
  vpc_id = aws_vpc.eks_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.eks_gateway.id
  }

  tags = {
    Name = "eks_route_table"
  }
}

resource "aws_route_table_association" "route_table_association" {
  count = length(var.subnet)
  subnet_id     = aws_subnet.eks_subnet[count.index].id
  route_table_id = aws_route_table.eks_route_table.id
}

resource "aws_subnet" "private_subnet" {
  count = length(var.private_subnet)
  vpc_id     = aws_vpc.eks_vpc.id
  cidr_block = var.private_subnet[count.index]["cidr_block"]
  availability_zone = var.private_subnet[count.index]["availability_zone"]
  map_public_ip_on_launch = false

  tags = {
    Name = var.private_subnet[count.index]["name"]
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}

resource "aws_eip" "nat" {
  vpc              = true
  count = length(var.private_subnet)
  public_ipv4_pool = "amazon"
}

resource "aws_nat_gateway" "nat_gateway" {
  count         = length(var.private_subnet)
  allocation_id = element(aws_eip.nat.*.id, count.index)
  subnet_id     = element(aws_subnet.eks_subnet.*.id, count.index)
  depends_on    = [aws_internet_gateway.eks_gateway]

  tags = {
    Name = "eks-nat_Gateway-${count.index + 1}"
  }
}

resource "aws_route_table" "nat-route" {
  vpc_id = aws_vpc.eks_vpc.id
  count  = length(var.private_subnet)
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = element(aws_nat_gateway.nat_gateway.*.id, count.index)
  }
  depends_on = [ aws_vpc.eks_vpc ]
  tags  = {
      Name = "eks-nat_route_table-${count.index + 1}"
      state = "public"
  } 
}

resource "aws_route_table_association" "private" {
  count          = length(var.private_subnet)
  subnet_id      = element(aws_subnet.private_subnet.*.id, count.index)
  route_table_id = element(aws_route_table.nat-route.*.id, count.index)
  depends_on = [ 
    aws_route_table.nat-route ,
    aws_subnet.private_subnet
  ]
}

resource "aws_security_group" "eks_security_group" {
  name        = "eks_security_group"
  description = "Main eks security group"
  vpc_id      = aws_vpc.eks_vpc.id

  dynamic ingress {
    for_each = var.eks_security_group["ports"]
    content {
      description = "TLS from VPC"
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = [var.eks_security_group["cidr_block"]]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "allow https"
  }
}

resource "aws_iam_role" "eks_cluster_iam_role" {
  name = "eks_cluster_iam_role"

  assume_role_policy = var.policies["eks_cluster_iam_role"]
}

resource "aws_iam_role_policy_attachment" "eks_cluster_AmazonEKSClusterPolicy" {
  count = length(var.eks_policy_arn)
  policy_arn = var.eks_policy_arn[count.index]
  role       = aws_iam_role.eks_cluster_iam_role.name
}

resource "aws_eks_cluster" "eks_cluster" {
  name     = var.cluster_name
  role_arn = aws_iam_role.eks_cluster_iam_role.arn
  version = "1.19"

  vpc_config {
    security_group_ids = [aws_security_group.eks_security_group.id]
    subnet_ids         = aws_subnet.eks_subnet[*].id
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_AmazonEKSClusterPolicy
  ]
}




