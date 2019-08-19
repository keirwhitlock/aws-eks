# Kubernetes Worker Nodes
data "aws_ami" "eks-worker" {
  filter {
    name   = "name"
    values = ["amazon-eks-node-1.13-v*"]
  }

  most_recent = true
  owners      = ["602401143452"] # Amazon EKS AMI Account ID
}

# Worker Node IAM Role and Instance Profile
resource "aws_iam_role" "eks-core-cluster-worker" {
  name = "eks-core-cluster-worker"

  assume_role_policy = <<POLICY
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

resource "aws_iam_role_policy_attachment" "eks-core-cluster-worker-AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role = aws_iam_role.eks-core-cluster-worker.name
}

resource "aws_iam_role_policy_attachment" "eks-core-cluster-worker-AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role = aws_iam_role.eks-core-cluster-worker.name
}

resource "aws_iam_role_policy_attachment" "eks-core-cluster-worker-AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role = aws_iam_role.eks-core-cluster-worker.name
}

resource "aws_iam_instance_profile" "eks-core-cluster-worker" {
  name = "eks-core-cluster-worker"
  role = aws_iam_role.eks-core-cluster-worker.name
}

# Worker Node Security Group

resource "aws_security_group" "eks-core-cluster-worker" {
  name = "eks-core-cluster-worker"
  description = "Security group for all nodes in the EKS cluster"
  vpc_id = data.terraform_remote_state.networking.outputs.vpc_id

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    "Name" = "eks-core-cluster-worker"
    "kubernetes.io/cluster/${var.cluster-name}" = "owned"
  }
}

resource "aws_security_group_rule" "worker-ingress-self" {
  description = "Allow node to communicate with each other"
  from_port = 0
  protocol = "-1"
  security_group_id = aws_security_group.eks-core-cluster-worker.id
  source_security_group_id = aws_security_group.eks-core-cluster-worker.id
  to_port = 65535
  type = "ingress"
}

resource "aws_security_group_rule" "worker-ingress-cluster" {
  description = "Allow worker Kubelets and pods to receive communication from the cluster control plane"
  from_port = 1025
  protocol = "tcp"
  security_group_id = aws_security_group.eks-core-cluster-worker.id
  source_security_group_id = aws_security_group.eks-core-cluster.id
  to_port = 65535
  type = "ingress"
}

resource "aws_security_group_rule" "eks-core-cluster-ingress-node-https" {
  description = "Allow pods to communicate with the cluster API Server"
  from_port = 443
  protocol = "tcp"
  security_group_id = aws_security_group.eks-core-cluster.id
  source_security_group_id = aws_security_group.eks-core-cluster-worker.id
  to_port = 443
  type = "ingress"
}

# Worker Node AutoScaling Group

locals {
  eks-core-cluster-worker-userdata = <<USERDATA
#!/bin/bash
set -o xtrace
/etc/eks/bootstrap.sh --apiserver-endpoint '${aws_eks_cluster.eks-core-cluster.endpoint}' --b64-cluster-ca '${aws_eks_cluster.eks-core-cluster.certificate_authority[0].data}' '${var.cluster-name}'
USERDATA

}

locals {
  root_block_device = {
    size = "32"
    min_threshold_tier_1 = "5"
    min_threshold_tier_2 = "0.5"
  }

  docker_block_device = {
    size = "100"
    min_threshold_tier_1 = "15"
    min_threshold_tier_2 = "0.5"
  }
}

resource "aws_launch_template" "eks-core-cluster" {
  name_prefix = "eks-core-cluster-worker-lt-"
  key_name = "DEV"
  image_id = data.aws_ami.eks-worker.id
  instance_initiated_shutdown_behavior = "terminate"
  vpc_security_group_ids = [aws_security_group.eks-core-cluster-worker.id]

  credit_specification {
    cpu_credits = "standard"
  }

  iam_instance_profile {
    name = aws_iam_instance_profile.eks-core-cluster-worker.name
  }

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_type = "gp2"
      volume_size = local.root_block_device["size"]
      encrypted = true
    }
  }

  block_device_mappings {
    device_name = "/dev/xvdcz"

    ebs {
      volume_type = "gp2"
      volume_size = local.docker_block_device["size"]
      encrypted = true
    }
  }

  monitoring {
    enabled = true
  }

  tag_specifications {
    resource_type = "instance"

    tags = {
        Name = "eks-core-cluster-worker"
      }
  }

  user_data = base64encode(local.eks-core-cluster-worker-userdata)

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "eks-core-cluster" {
name                 = "eks-core-cluster"
desired_capacity     = 3
max_size             = 3
min_size             = 1
force_delete         = true
termination_policies = ["OldestInstance"]
vpc_zone_identifier = [
data.terraform_remote_state.networking.outputs.subnet_id_a,
data.terraform_remote_state.networking.outputs.subnet_id_b,
data.terraform_remote_state.networking.outputs.subnet_id_c,
]

tag {
key                 = "Name"
value               = "eks-core-cluster"
propagate_at_launch = true
}

tag {
key                 = "kubernetes.io/cluster/${var.cluster-name}"
value               = "owned"
propagate_at_launch = true
}

  mixed_instances_policy {

    launch_template {
      launch_template_specification {
        launch_template_id = aws_launch_template.eks-core-cluster.id
        version = "$Latest"
      }

      override {
        instance_type = var.linux_instance_types_list[0]
      }

      override {
        instance_type = var.linux_instance_types_list[1]
      }

    }

    instances_distribution {
      on_demand_percentage_above_base_capacity = 0
    }

  } // mixed_instance_policy


}

locals {
config_map_aws_auth = <<CONFIGMAPAWSAUTH


apiVersion: v1
kind: ConfigMap
metadata:
  name: aws-auth
  namespace: kube-system
data:
  mapRoles: |
    - rolearn: ${aws_iam_role.eks-core-cluster-worker.arn}
      username: system:node:{{EC2PrivateDNSName}}
      groups:
        - system:bootstrappers
        - system:nodes
CONFIGMAPAWSAUTH

}

# provisioner "local-exec" {
#   command = "aws --region "${local.region}" --profile "${local.profile}" eks update-kubeconfig --name "${aws_eks_cluster.eks-core-cluster.name}""
# }

output "config_map_aws_auth" {
value = local.config_map_aws_auth
}

