resource "aws_iam_policy" "s3_access" {
  name = "streamingapp-s3-access"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:GetObject",
        "s3:PutObject",
        "s3:ListBucket",
      ]
      Resource = [
        aws_s3_bucket.videos.arn,
        "${aws_s3_bucket.videos.arn}/*",
      ]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "node_s3_access" {
  role       = module.eks.eks_managed_node_groups["default"].iam_role_name
  policy_arn = aws_iam_policy.s3_access.arn
}
