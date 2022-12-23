output "private_ip" {
  value = aws_instance.k3s_server.private_ip
  description = "Private IP of the EC2 instance"
}

output "public_ip" {
  value = aws_instance.k3s_server.public_ip
  description = "Public IP of the EC2 instance"
}

output "id" {
  value = aws_instance.k3s_server.id
  description = "ID of EC2 instance"
}