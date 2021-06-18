
resource "aws_iam_user" "cert_manager" {
  name = "cert-manager"
}

resource "aws_iam_user_policy" "cert_manager_iam_policy" {
  name = "cert-manager-iam-policy"
  user = aws_iam_user.cert_manager.name

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect: "Allow",
        Action: "route53:GetChange",
        Resource: "arn:aws:route53:::change/*"
      },
      {
        Effect: "Allow",
        Action = [
          "route53:ChangeResourceRecordSets",
          "route53:ListResourceRecordSets"
        ],
        Resource = "arn:aws:route53:::hostedzone/*"
      },
      {
        Effect = "Allow",
        Action = "route53:ListHostedZonesByName",
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_access_key" "cert_manager_access_key" {
  user = aws_iam_user.cert_manager.name
}