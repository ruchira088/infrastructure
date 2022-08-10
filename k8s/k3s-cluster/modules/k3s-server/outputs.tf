output "private_ip" {
  value = aws_instance.k3s_server.private_ip
  description = "Private IP of the EC2 instance"
}

output "id" {
  value = aws_instance.k3s_server.id
  description = "ID of EC2 instance"
}