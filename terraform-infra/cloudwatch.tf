resource "aws_cloudwatch_log_group" "lambda_logs" {
  for_each = {
    parser = aws_lambda_function.openvas_parser.function_name
    api    = aws_lambda_function.dynamodb_read.function_name
  }

  name              = "/aws/lambda/${each.value}"
  retention_in_days = 7
}