# Common tags applied to all AWS resources
variable "access_key" {
    type         = string
    description  = "AWS Accesss Key"
    sensitive    = true

}
variable "secret_key" {
    type         = string
    description  = "AWS Secret Key"
    sensitive    = true
}
variable "aws_region" {
    type         = string
    description  = "AWS Region"
    default = "us-east-1"
}

variable "tags" {
  description = "AWS Tags to apply to appropriate resources."
  type        = map(string)
  default     = {}
}

# Default application tags for non-infrastructure resources
variable "application_tags" {
  description = "Default application tags to be used on non-infrastructure resources."
  type        = map(string)
  default     = {}
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = ""
}


data "aws_caller_identity" "current" {}

data "aws_arn" "current" {
  arn = data.aws_caller_identity.current.arn
}

data "aws_region" "current" {}

# # VPC and CIDR Configuration
# variable "vpc_full_name" {
#   description = "Full name component used throughout the VPC"
#   type        = string
#   default     = ""
# }

# variable "census_public_cidr" {
#   description = "CIDR blocks for public subnets"
#   type        = list(string)
#   default     = ["XXX.XXX.X.X/16"]
# }

variable "tag_costallocation" {
  description = "Tag CostAllocation (default)"
  type        = string
  default     = "mytag:sometag"
}

variable "cluster_name" {
  description = "Cluster Name"
  type        = string
  default     = "Cluster-0001"
}

# Local Variables
locals {
  common_tags = {
    Environment    = "infrastructure"
    CostAllocation = var.tag_costallocation
    "boc:created_by" = "terraform"
  }
}

locals {
  _prefixes = {
    "eks-role" = "mp-eks-role-"
    "eks"      = "mp-eks-"
  }
}

# EKS Configuration
# variable "shared_vpc_label" {
#   description = "Label for shared VPC"
#   type        = string
#   default     = ""
# }

variable "eks_instance_type" {
  description = "EC2 instance type for the EKS node group"
  type        = string
  default     = "t2.small"
}

variable "eks_instance_disk_size" {
  description = "Disk size for the EKS node group instances"
  type        = number
  default     = 30
}
