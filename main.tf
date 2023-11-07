locals {
  vpc_id         = data.aws_vpc.eks_vpc.id
  vpc_cidr_block = data.aws_vpc.eks_vpc.cidr_block
  eks_vpc_name           = "Kubernetes"
  subnets_name  = "Kubernetes-subnet-public3-us-east-1c"
  # census_public_cidr = ["xxx.xxx.xxx.xxx"]
  subnets        = ["subnet-0fea7b813db8e884d","subnet-0379b836f2b8d8aa2"]
  # s3_base_arn    = format("arn:%v:%v:::%%v", data.aws_arn.current.partition, "s3")

  base_tags = {
    "eks-cluster-name"      = var.cluster_name
    "xxx:tf_module_version" = local._module_version
    "xxx:created_by"        = "terraform"
  }
  # https://docs.aws.amazon.com/eks/latest/userguide/cluster-autoscaler.html
  autoscale_tags = {
    format("k8s.io/cluster-autoscaler/%v", var.cluster_name) = "owned"
    "k8s.io/cluster-autoscaler/enabled"                      = "TRUE"
  }
}

locals {
  _module_version = "1.0.0"
}

data "aws_vpc" "eks_vpc" {
  filter {
    name   = "tag:Name"
    values = [local.eks_vpc_name]
  }
}
data "aws_subnets" "subnets" {
  filter {
    name   = "tag:Name"
    values = [local.subnets_name]
  }
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.eks_vpc.id]
  }
}
data "aws_subnet" "subnets" {
  for_each = toset(data.aws_subnets.subnets.ids)
  id       = each.key
}
data "aws_ebs_default_kms_key" "current" {}
data "aws_kms_key" "ebs_key" {
  key_id = data.aws_ebs_default_kms_key.current.key_arn
}
# The log group name format is /aws/eks/<cluster-name>/cluster
# Reference: https://docs.aws.amazon.com/eks/latest/userguide/control-plane-logs.html
## cluster 
resource "aws_cloudwatch_log_group" "eks-cluster-log" {
  name              = format("/aws/eks/%v/cluster", var.cluster_name)
  retention_in_days = 180
  tags = merge(
    local.base_tags,
    local.common_tags,
    var.tags,
    var.application_tags,
  )
}
resource "aws_iam_role" "eks-cluster-role" {
  name = format("%v%v-cluster-role", local._prefixes["eks-role"], var.cluster_name)
  assume_role_policy = <<POLICY
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
}
resource "aws_iam_role_policy_attachment" "eks-cluster-AmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks-cluster-role.name
}
resource "aws_iam_role_policy_attachment" "eks-cluster-AmazonEC2FullAccess" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2FullAccess"
  role       = aws_iam_role.eks-cluster-role.name
}
resource "aws_iam_role_policy_attachment" "eks-cluster-CloudWatchLogsFullAccess" {
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
  role       = aws_iam_role.eks-cluster-role.name
}

resource "aws_security_group" "extra_cluster_sg" {
  name_prefix = "extra-cluster-sg-"
  description = "Security group for the EKS cluster"
  vpc_id     = data.aws_vpc.eks_vpc.id
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  // Add any other necessary configuration for your security group
}


resource "aws_eks_cluster" "eks-cluster" {
  name     = var.cluster_name
  role_arn = aws_iam_role.eks-cluster-role.arn
  vpc_config {
    subnet_ids              = local.subnets
    endpoint_public_access  = true
    endpoint_private_access = true
    public_access_cidrs     = ["73.34.129.221/32", "174.51.39.60/32"]
    security_group_ids      = [aws_security_group.extra_cluster_sg.id]
  }
  tags = merge(
    local.base_tags,
    local.common_tags,
    var.tags,
    var.application_tags,
  )
  depends_on = [aws_iam_role_policy_attachment.eks-cluster-AmazonEKSClusterPolicy,
    aws_iam_role_policy_attachment.eks-cluster-AmazonEC2FullAccess,
    aws_iam_role_policy_attachment.eks-cluster-CloudWatchLogsFullAccess
  ]
}
##- nodes
resource "aws_iam_role" "eks-worker-node-role" {
  name = format("%v%v-worker-node-role", local._prefixes["eks-role"], var.cluster_name)
  assume_role_policy = jsonencode({
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
    Version = "2012-10-17"
  })
  tags = merge(
    local.base_tags,
    local.common_tags,
    var.tags,
    var.application_tags,
  )
}
resource "aws_iam_role_policy_attachment" "eks-worker-nodes-AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks-worker-node-role.name
}
resource "aws_iam_role_policy_attachment" "eks-worker-nodes-AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks-worker-node-role.name
}
resource "aws_iam_role_policy_attachment" "eks-worker-nodes-AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks-worker-node-role.name
}
resource "aws_iam_role_policy_attachment" "eks-worker-nodes-AmazonEC2ContainerRegistryPowerUser" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser"
  role       = aws_iam_role.eks-worker-node-role.name
}
resource "aws_iam_role_policy_attachment" "eks-worker-nodes-CloudWatchLogsFullAccess" {
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
  role       = aws_iam_role.eks-worker-node-role.name
}
resource "aws_iam_role_policy_attachment" "eks-worker-nodes-AmazonS3FullAccess" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
  role       = aws_iam_role.eks-worker-node-role.name
}
resource "aws_iam_role_policy_attachment" "eks-worker-nodes-AmazonSSMManagedInstanceCore" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = aws_iam_role.eks-worker-node-role.name
}
/*
resource "aws_iam_role_policy_attachment" "eks-worker-nodes-AmazonEC2RoleforSSM" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2RoleforSSM"
  role       = aws_iam_role.eks-worker-node-role.name
}
*/
resource "aws_eks_node_group" "eks-worker-nodes" {
  cluster_name    = aws_eks_cluster.eks-cluster.name
  node_group_name = format("%v%v-nodegroup", local._prefixes["eks"], var.cluster_name)
  node_role_arn   = aws_iam_role.eks-worker-node-role.arn
  subnet_ids    = local.subnets
  capacity_type = "ON_DEMAND"
  scaling_config {
    desired_size = 1
    max_size     = 5
    min_size     = 0
  }
  update_config {
    max_unavailable = 1
  }
  labels = {
    role = "general"
  }
  launch_template {
    id      = aws_launch_template.eks-nodegroup-launch-template.id
    version = aws_launch_template.eks-nodegroup-launch-template.latest_version
  }
  tags = merge(
    local.base_tags,
    local.common_tags,
    var.tags,
    var.application_tags,
    local.autoscale_tags,
  )
  lifecycle {
    ignore_changes = [launch_template]
  }
  # Ensure that IAM Role permissions are created before and deleted after EKS Node Group handling.
  # Otherwise, EKS will not be able to properly delete EC2 Instances and Elastic Network Interfaces.
  depends_on = [
    aws_iam_role_policy_attachment.eks-worker-nodes-AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.eks-worker-nodes-AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.eks-worker-nodes-AmazonEC2ContainerRegistryReadOnly,
    aws_iam_role_policy_attachment.eks-worker-nodes-AmazonEC2ContainerRegistryPowerUser,
    aws_iam_role_policy_attachment.eks-worker-nodes-CloudWatchLogsFullAccess,
    aws_iam_role_policy_attachment.eks-worker-nodes-AmazonS3FullAccess,
    aws_iam_role_policy_attachment.eks-worker-nodes-AmazonSSMManagedInstanceCore,
    #  aws_iam_role_policy_attachment.eks-worker-nodes-AmazonEC2RoleforSSM,
  ]
}
locals {
  launch_template_tags = {
    "Name"                                               = format("%v%v-nodegroup-instance-name", local._prefixes["eks"], var.cluster_name)
    format("kubernetes.io/cluster/%v", var.cluster_name) = "owned"
  }
}
resource "aws_launch_template" "eks-nodegroup-launch-template" {
  instance_type          = var.eks_instance_type
  name                   = format("%v%v-launch-template", local._prefixes["eks"], var.cluster_name)
  update_default_version = true
  vpc_security_group_ids = [aws_security_group.extra_cluster_sg.id]
  tags = merge(
    local.base_tags,
    local.common_tags,
    var.tags,
    var.application_tags,
  )
  tag_specifications {
    resource_type = "instance"
    tags = merge(
      local.base_tags,
      tomap({ "xxx:created_by" = "eks-launch-template" }),
      local.common_tags,
      local.launch_template_tags,
      var.tags,
    )
  }
  tag_specifications {
    resource_type = "volume"
    tags = merge(
      local.base_tags,
      tomap({ "xxx:created_by" = "eks-launch-template" }),
      local.common_tags,
      var.tags,
      var.application_tags,
    )
  }
  tag_specifications {
    resource_type = "network-interface"
    tags = merge(
      local.base_tags,
      tomap({ "xxx:created_by" = "eks-launch-template" }),
      local.common_tags,
      var.tags,
      var.application_tags,
    )
  }
  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = var.eks_instance_disk_size
      delete_on_termination = true
      encrypted             = true
      kms_key_id            = data.aws_kms_key.ebs_key.arn
    }
  }
  user_data = base64encode(local.eks-worker-node-userdata)
}
#### User data for worker launch
locals {
  eks-worker-node-userdata = templatefile(
    "worker-node-userdata.tmpl", {
      endpoint     = aws_eks_cluster.eks-cluster.endpoint
      cluster_ca   = aws_eks_cluster.eks-cluster.certificate_authority[0].data
      cluster_name = var.cluster_name
    }
  )
}
## Dummy VPC
#---
# dummy vpc, so we can associate the zone to this account
#---
# data "aws_vpc" "dummy_vpc" {
#   count =  (var.shared_vpc_label == null || var.shared_vpc_label == "") ? 1 : 0
#   filter {
#     name   = "tag:Name"
#     values = ["vpc0-dummy"]
#   }
# }
# resource "aws_vpc" "vpc" {
#   cidr_block           = "10.0.32.0/20"
#   enable_dns_support   = false
#   enable_dns_hostnames = false
#   tags = merge(
#     local.base_tags,
#     { "Name" = "vpc0-dummy" },
#   )
# }

