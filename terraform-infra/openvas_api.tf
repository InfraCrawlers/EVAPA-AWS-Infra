resource "aws_api_gateway_rest_api" "openvas_gw" {
  name        = "OpenVAS-Automation-API"
  description = "Serverless API to trigger and manage OpenVAS scans"
}

locals {
  api_routes = {
    "port-lists" = { lambda_key = "create_port_list", method = "POST" }
    "targets"    = { lambda_key = "create_target",    method = "POST" }
    "tasks"      = { lambda_key = "create_task",      method = "POST" }
  }
}

# 2. Create the URL paths (Resources)
resource "aws_api_gateway_resource" "api_routes" {
  for_each    = local.api_routes
  rest_api_id = aws_api_gateway_rest_api.openvas_gw.id
  parent_id   = aws_api_gateway_rest_api.openvas_gw.root_resource_id
  path_part   = each.key
}

# 3. Assign the HTTP Method (POST)
resource "aws_api_gateway_method" "api_methods" {
  for_each      = local.api_routes
  rest_api_id   = aws_api_gateway_rest_api.openvas_gw.id
  resource_id   = aws_api_gateway_resource.api_routes[each.key].id
  http_method   = each.value.method
  authorization = "NONE"
}

# 4. Connect the API path to the correct Lambda function
resource "aws_api_gateway_integration" "api_integrations" {
  for_each                = local.api_routes
  rest_api_id             = aws_api_gateway_rest_api.openvas_gw.id
  resource_id             = aws_api_gateway_resource.api_routes[each.key].id
  http_method             = aws_api_gateway_method.api_methods[each.key].http_method
  integration_http_method = "POST" # Lambda proxy integration always requires POST
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.openvas_api[each.value.lambda_key].invoke_arn
}

# 5. Grant API Gateway permission to trigger these Lambdas
resource "aws_lambda_permission" "apigw_invoke_lambdas" {
  for_each      = local.api_routes
  statement_id  = "AllowExecutionFromAPIGateway_${each.key}"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.openvas_api[each.value.lambda_key].function_name
  principal     = "apigateway.amazonaws.com"
  
  # The /*/* allows invocation from any stage and method on this API
  source_arn = "${aws_api_gateway_rest_api.openvas_gw.execution_arn}/*/*"
}

# 6. Grant permission for the "Start Scan" Lambda (which has a custom path)
resource "aws_lambda_permission" "apigw_invoke_start_scan" {
  statement_id  = "AllowExecutionFromAPIGateway_start_scan"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.openvas_api["start_scan"].function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.openvas_gw.execution_arn}/*/*"
}

# 7. Deploy the API 
resource "aws_api_gateway_deployment" "api_deployment" {
  rest_api_id = aws_api_gateway_rest_api.openvas_gw.id

  # This lifecycle rule ensures zero downtime when Terraform updates the API
  lifecycle {
    create_before_destroy = true
  }
  
  # Ensure all integrations are built before trying to deploy
  depends_on = [
    aws_api_gateway_integration.api_integrations
  ]
}

# 8. Create a Stage (e.g., "v1" or "dev")
resource "aws_api_gateway_stage" "api_stage" {
  deployment_id = aws_api_gateway_deployment.api_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.openvas_gw.id
  stage_name    = "v1"
}

# 9. Output the final URL you will use to call the API
