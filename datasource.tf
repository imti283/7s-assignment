###################################################
########       Data Source            #############
###################################################
data "aws_ami" "amazon_linux_2" {
  most_recent = true

  filter {
    name   = "owner-alias"
    values = ["amazon"]
  }

  filter {
    name   = "name"
    values = ["amzn2-ami-kernel-5*-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  owners = ["137112412989"]
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnet_ids" "default_public_subnet" {
  vpc_id = data.aws_vpc.default.id
  filter {
    name   = "default-for-az"
    values = [true]
  }
}

data "aws_availability_zones" "available" {}

###################################################
########      variables               #############
###################################################
variable "access_key" {
}

variable "secret_key" {
}

variable "key_name" {
}