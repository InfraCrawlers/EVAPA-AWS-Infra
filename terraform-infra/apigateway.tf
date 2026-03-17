resource "aws_apigatewayv2_api" "openvas_api" {

  name          = "openvas-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_methods = ["GET"]
    allow_origins = ["*"]
    allow_headers = ["*"]
  }
}

resource "aws_apigatewayv2_integration" "lambda_integration" {

  api_id           = aws_apigatewayv2_api.openvas_api.id
  integration_type = "AWS_PROXY"

  integration_uri = aws_lambda_function.dynamodb_read.invoke_arn
}

resource "aws_apigatewayv2_route" "get_findings" {

  api_id    = aws_apigatewayv2_api.openvas_api.id
  route_key = "GET /findings"

  target = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

resource "aws_apigatewayv2_stage" "api_stage" {

  api_id      = aws_apigatewayv2_api.openvas_api.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_lambda_permission" "api_invoke" {

  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.dynamodb_read.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_apigatewayv2_api.openvas_api.execution_arn}/*/*"
}