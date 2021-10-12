resource "aws_iam_user" "github_actions" {
  name = "github-actions"
}

resource "aws_iam_user_policy_attachment" "github_actions_policy_attachment" {
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
  user       = aws_iam_user.github_actions.name
}

resource "aws_iam_access_key" "github_actions_access_key" {
  user = aws_iam_user.github_actions.name
}

resource "aws_ssm_parameter" "github_actions_access_key_id" {
  name  = "/github/aws/access-key-id"
  type  = "SecureString"
  value = aws_iam_access_key.github_actions_access_key.id
}

resource "aws_ssm_parameter" "github_actions_secret_access_key" {
  name  = "/github/aws/secret-access-key"
  type  = "SecureString"
  value = aws_iam_access_key.github_actions_access_key.secret
}