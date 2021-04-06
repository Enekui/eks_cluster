variable "cluster_name" {
  type = string
  default = "eks_cluster"
}

variable "region" {
  type = string
  default = "eu-central-1"
}

variable "vpc" {
  type = map
  default = {
    name = "eks_vpc",
    cidr_block = "172.16.0.0/16",
    instance_tenancy = "default"
  }
}

variable "subnet" {
  default = [
    { 
      cidr_block = "172.16.1.0/24",
      name = "eks_subnet_a",
      availability_zone = "eu-central-1a"
    },

    {
      cidr_block = "172.16.2.0/24",
      name = "eks_subnet_b",
      availability_zone = "eu-central-1b"
    }
  ]
}

variable "eks_security_group" {
  default = {
    cidr_block = "0.0.0.0/32"
    name = "eks_security_group",
    ports = [
      443,
    ]
  }
}

variable "workers_security_group" {

  default = {
    name = "workers_security_group"
  }
}

variable "policies" {

  default = {
  eks_cluster_iam_role = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "eks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
POLICY
  eks_iam_role_worker = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
POLICY
  } 
}

variable "eks_policy_arn" {
  type = list(string)
  default = [
    "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy",
    "arn:aws:iam::aws:policy/AmazonEKSServicePolicy"
  ]
}

variable "worker_pocly_arn" {
  type = list(string)
  default = [
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  ]
}


