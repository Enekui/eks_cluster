resource "aws_security_group" "workers_security_group" {
  name        = var.workers_security_group["name"]
  description = "Security group for all workers in the cluster"
  vpc_id      = aws_vpc.eks_vpc.id

  dynamic ingress {
    for_each = var.workers_security_group["ports"]
    content {
        cidr_blocks       = ["0.0.0.0/0"]
        description       = "Allow outside traffic"
        from_port         = ingress.value
        protocol          = "tcp"
        to_port           = ingress.value
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    "Name"                                      = var.workers_security_group["name"]
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }
}

resource "aws_security_group_rule" "eks_self_ingress" {
  description              = "Allow node to communicate with each other"
  from_port                = 0
  protocol                 = "-1"
  security_group_id        = aws_security_group.workers_security_group.id
  source_security_group_id = aws_security_group.workers_security_group.id
  to_port                  = 65535
  type                     = "ingress"
}

resource "aws_security_group_rule" "eks_ingress_cluster" {
  description              = "Allow worker Kubelets and pods to receive communication from the cluster control plane"
  from_port                = 1025
  protocol                 = "tcp"
  security_group_id        = aws_security_group.workers_security_group.id
  source_security_group_id = aws_security_group.eks_security_group.id
  to_port                  = 65535
  type                     = "ingress"
}

resource "aws_security_group_rule" "eks_ingress_node_https" {
  description              = "Allow pods to communicate with the cluster API Server"
  from_port                = 443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.eks_security_group.id
  source_security_group_id = aws_security_group.workers_security_group.id
  to_port                  = 443
  type                     = "ingress"
}

resource "aws_iam_role" "eks_iam_role_worker" {
  name = "eks_iam_role_worker"

  assume_role_policy = var.policies["eks_iam_role_worker"]
}

resource "aws_iam_role_policy_attachment" "eks_worker_policy" {
  count = length(var.worker_pocly_arn)
  policy_arn = var.worker_pocly_arn[count.index]
  role       = aws_iam_role.eks_iam_role_worker.name
}

resource "aws_eks_node_group" "eks_node_group" {
  cluster_name    = aws_eks_cluster.eks_cluster.name
  node_group_name = "eks_node_group"
  node_role_arn   = aws_iam_role.eks_iam_role_worker.arn
  subnet_ids      = aws_subnet.eks_subnet[*].id
  instance_types = [ "t3.medium" ]


  scaling_config {
    desired_size = 1
    max_size     = 1
    min_size     = 1
  }

  # Ensure that IAM Role permissions are created before and deleted after EKS Node Group handling.
  # Otherwise, EKS will not be able to properly delete EC2 Instances and Elastic Network Interfaces.
  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_policy
  ]
}