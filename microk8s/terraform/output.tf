output "cert_manager_user_access_key_id" {
  value = aws_iam_access_key.cert_manager_access_key.id
}

output "cert_manager_user_secret_access_key" {
  value = aws_iam_access_key.cert_manager_access_key.secret
  sensitive = true
}