resource "aws_security_group" "workers_security_group" {
  name        = var.workers_security_group["name"]
  description = "Security group for all workers in the cluster"
  vpc_id      = aws_vpc.eks_vpc.id

  ingress {
    cidr_blocks       = ["0.0.0.0/0"]
    description       = "Allow workstation connect to nodes by SSH"
    from_port         = 22
    protocol          = "tcp"
    to_port           = 22
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

data "aws_ami" "worker_ami" {
  filter {
    name   = "name"
    values = ["amazon-eks-node-${aws_eks_cluster.eks_cluster.version}-v*"]
  }

  most_recent = true
  owners      = ["602401143452"] # Amazon EKS AMI Account ID
}

# EKS currently documents this required userdata for EKS worker nodes to
# properly configure Kubernetes applications on the EC2 instance.
# We implement a Terraform local here to simplify Base64 encoding this
# information into the AutoScaling Launch Configuration.
# More information: https://docs.aws.amazon.com/eks/latest/userguide/launch-workers.html
locals {
  node_configuration = <<USERDATA
#!/bin/bash
set -o xtrace
/etc/eks/bootstrap.sh --apiserver-endpoint '${aws_eks_cluster.eks_cluster.endpoint}' --b64-cluster-ca '${aws_eks_cluster.eks_cluster.certificate_authority[0].data}' '${var.cluster_name}'
USERDATA
}

resource "aws_iam_instance_profile" "worker_instance_profile" {
  name = "worker_instance_profile"
  role = aws_iam_role.eks_iam_role_worker.name
}

resource "aws_key_pair" "eks_key" {
  key_name   = "eks_key"
  public_key = file("~/.ssh/id_rsa.pub")
}

resource "aws_launch_configuration" "workres_configuration" {
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.worker_instance_profile.name
  image_id                    = data.aws_ami.worker_ami.id
  instance_type               = "t3.medium"
  name_prefix                 = "worker"
  security_groups             = [aws_security_group.workers_security_group.id]
  user_data_base64            = base64encode(local.node_configuration)
  key_name                    = aws_key_pair.eks_key.key_name

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "workers_autoscaling_group" {
  desired_capacity     = 2
  launch_configuration = aws_launch_configuration.workres_configuration.id
  max_size             = 2
  min_size             = 1
  name                 = "workres_autoscaling"
  vpc_zone_identifier  = aws_subnet.eks_subnet.*.id

  tag {
    key                 = "Name"
    value               = "workers_auto_scaling"
    propagate_at_launch = true
  }

  tag {
    key                 = "kubernetes.io/cluster/${var.cluster_name}"
    value               = "owned"
    propagate_at_launch = true
  }
}