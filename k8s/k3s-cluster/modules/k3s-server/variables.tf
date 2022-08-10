variable "availability_zone" {
  type = string
  description = "The availability zone of the EC2 instance"
}

variable "ec2_name" {
  type = string
  description = "Name of the EC2 instance"
}

variable "init_script" {
  type = string
  description = "Initialization script to be executed"
}