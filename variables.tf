variable "cluster-name" {
  default = "eks-core-cluster"
  type    = string
}

variable "linux_instance_types_list" {
  default = ["t2.large", "t3.large"]
  type = list
}
