resource "aws_eks_fargate_profile" "eks_fargate_profile" {
  cluster_name           = aws_eks_cluster.eks_cluster.name
  fargate_profile_name   = "eks_fargate_profile"
  pod_execution_role_arn = aws_iam_role.eks_iam_fargate_role.arn
  subnet_ids             = [for s in aws_subnet.private_subnet.*.id : s]

  dynamic selector {
    for_each = var.fargate_selector
    content {
      namespace = selector.value
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.fargate-AmazonEKSFargatePodExecutionRolePolicy
  ]
}

resource "aws_iam_role" "eks_iam_fargate_role" {
  name = "eks-fargate-role"

  assume_role_policy = var.policies["eks_iam_fargate_role"]
}

resource "aws_iam_role_policy_attachment" "fargate-AmazonEKSFargatePodExecutionRolePolicy" {
  count = length(var.fargate_policy_arn)
  policy_arn = var.fargate_policy_arn[count.index]
  role       = aws_iam_role.eks_iam_fargate_role.name
}