locals {
  key_name = "My MacBook Pro"
  vpc_name = "ruchira-vpc"
}

resource "random_uuid" "k3s_token" {}

data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = [ "ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*" ]
  }

  filter {
    name   = "virtualization-type"
    values = [ "hvm" ]
  }

  owners = ["099720109477"] # Canonical
}

data "aws_security_group" "public_security_group" {
  name = "public-sg"
}

data "aws_vpc" "vpc" {
}

data "aws_subnet" "public_subnet" {
  vpc_id = data.aws_vpc.vpc.id
  availability_zone = var.availability_zone

  tags = {
    "Type" = "public"
  }
}

resource "aws_instance" "k3s_server" {
  ami = data.aws_ami.ubuntu.id
  instance_type = "t3a.medium"

  key_name = local.key_name

  root_block_device {
    volume_size = 40
    volume_type = "gp3"
    delete_on_termination = true
  }

  subnet_id = data.aws_subnet.public_subnet.id

  vpc_security_group_ids = [ data.aws_security_group.public_security_group.id ]

  associate_public_ip_address = true

  availability_zone = var.availability_zone

  tags = {
    Name = var.ec2_name
  }

  user_data = var.init_script
}