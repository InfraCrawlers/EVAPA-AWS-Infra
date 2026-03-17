resource "aws_lambda_function" "openvas_parser" {

  function_name = "new_s3triggerforlambda"
  runtime       = "python3.11"
  handler       = "openvas_lambda.lambda_handler"

  memory_size = 128
  timeout     = 60

  role = aws_iam_role.lambda_role.arn

  filename         = "${path.module}/lambda/openvas_parser/openvas_lambda.zip"
  source_code_hash = filebase64sha256("${path.module}/lambda/openvas_parser/openvas_lambda.zip")

  environment {
    variables = {
      DYNAMODB_TABLE_NAME = aws_dynamodb_table.openvas_scan_findings.name
    }
  }

  depends_on = [
    aws_iam_role_policy.lambda_policy
  ]
}

resource "aws_lambda_permission" "allow_s3" {

  statement_id  = "AllowExecutionFromS3"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.openvas_parser.function_name
  principal     = "s3.amazonaws.com"

  source_arn = aws_s3_bucket.s3_openvas_reports.arn
}

resource "aws_s3_bucket_notification" "openvas_trigger" {
  bucket = aws_s3_bucket.s3_openvas_reports.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.openvas_parser.arn
    events              = ["s3:ObjectCreated:*"]

    filter_prefix = "openvas-reports/"
    filter_suffix = ".xml"
  }

  depends_on = [aws_lambda_permission.allow_s3]
}