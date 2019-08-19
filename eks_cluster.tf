# EKS Master Cluster IAM Role & Policies
resource "aws_iam_role" "eks-core-cluster" {
  name = "eks-core-cluster"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "eks.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF

}

resource "aws_iam_role_policy_attachment" "eks-core-cluster-AmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role = aws_iam_role.eks-core-cluster.name
}

resource "aws_iam_role_policy_attachment" "eks-core-cluster-AmazonEKSServicePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSServicePolicy"
  role = aws_iam_role.eks-core-cluster.name
}

# EKS Master Cluster Security Group
resource "aws_security_group" "eks-core-cluster" {
  name = "eks-core-cluster"
  description = "EKS communication between master & worker nodes."
  vpc_id = data.terraform_remote_state.networking.outputs.vpc_id

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "eks-core-cluster"
  }
}

# EKS Master Cluster

resource "aws_eks_cluster" "eks-core-cluster" {
  name = "eks-core-cluster"
  role_arn = aws_iam_role.eks-core-cluster.arn
  version = "1.13"

  vpc_config {
    endpoint_private_access = true
    endpoint_public_access  = true
    subnet_ids = [
      data.terraform_remote_state.networking.outputs.subnet_id_a,
      data.terraform_remote_state.networking.outputs.subnet_id_b,
      data.terraform_remote_state.networking.outputs.subnet_id_c,
    ]
    security_group_ids = [aws_security_group.eks-core-cluster.id]
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks-core-cluster-AmazonEKSClusterPolicy,
    aws_iam_role_policy_attachment.eks-core-cluster-AmazonEKSServicePolicy,
  ]
}

locals {
  kubeconfig = <<KUBECONFIG
aws --region "${local.region}" --profile "${local.profile}" eks update-kubeconfig --name "${aws_eks_cluster.eks-core-cluster.name}"
KUBECONFIG


kubecmd = <<KUBECMD
AWS_PROFILE="${local.profile}" kubectl get svc
KUBECMD

}

output "setup_kubeconfig" {
value = local.kubeconfig
}

output "test_kubeconfig" {
value = local.kubecmd
}

