data "archive_file" "lambda_zip" {
  type        = "zip"
  # Point this to the folder containing your index.mjs
  source_dir  = "${path.module}/lambda/dynamodb_api/" 
  
  # Output the zip to the root of your terraform module
  output_path = "${path.module}/lambda/dynamodb_api/dynamodb_read_payload.zip" 
}

resource "aws_lambda_function" "dynamodb_read" {
  function_name = "dynamodb-read"
  runtime       = "nodejs20.x"
  handler       = "index.handler" 
  role          = aws_iam_role.lambda_role.arn

  # Point these directly to the output of the archive_file data source
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

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