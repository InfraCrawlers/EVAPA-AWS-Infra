resource "aws_lambda_function" "dynamodb_read" {

  function_name = "dynamodb-read"
  runtime       = "nodejs20.x"
  handler       = "lambda.handler"

  role = aws_iam_role.lambda_role.arn

  filename         = "${path.module}/lambda/dynamodb_api/dynamodb_read.zip"
  source_code_hash = filebase64sha256("${path.module}/lambda/dynamodb_api/dynamodb_read.zip")

  memory_size = 128
  timeout     = 3
}

resource "aws_iam_role_policy" "lambda_dynamodb_read" {

  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:Scan",
          "dynamodb:Query",
          "dynamodb:GetItem"
        ]
        Resource = aws_dynamodb_table.openvas_scan_findings.arn
      }
    ]
  })
}