variable "availability_zone" {
  type        = string
  description = "The availability zone of the EC2 instance"
}

variable "ec2_name" {
  type        = string
  description = "Name of the EC2 instance"
}

variable "volume_size" {
  type        = number
  description = "Size of root volume"
  default     = 40
}

variable "instance_type" {
  type        = string
  description = "Instance type of the K3s server"
  default     = "t3a.medium"
}

variable "init_script" {
  type        = string
  description = "Initialization script to be executed"
}