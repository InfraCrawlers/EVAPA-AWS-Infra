resource "aws_api_gateway_rest_api" "openvas_gw" {
  name        = "OpenVAS-Automation-API"
  description = "Serverless API to trigger and manage OpenVAS scans"
}

locals {
  # 1. The unique URL paths (Creates the Resources)
  api_paths = toset(["port-lists", "targets", "tasks"])

  # 2. The endpoint combinations (Creates the Methods and Integrations)
  api_endpoints = {
    "port-lists_POST" = { path = "port-lists", method = "POST", lambda = "create_port_list" }
    "port-lists_GET"  = { path = "port-lists", method = "GET",  lambda = "get_port_lists" }
    "targets_POST"    = { path = "targets",    method = "POST", lambda = "create_target" }
    "targets_GET"     = { path = "targets",    method = "GET",  lambda = "get_targets" }
    "tasks_POST"      = { path = "tasks",      method = "POST", lambda = "create_task" }
    "tasks_GET"       = { path = "tasks",      method = "GET",  lambda = "get_tasks" }
  }
}

# 2. Create the URL paths (Resources) - Terraform builds these 3 paths first
resource "aws_api_gateway_resource" "api_routes" {
  for_each    = local.api_paths
  rest_api_id = aws_api_gateway_rest_api.openvas_gw.id
  parent_id   = aws_api_gateway_rest_api.openvas_gw.root_resource_id
  path_part   = each.key
}

# 3. Assign the HTTP Methods (POST & GET) to their respective paths
resource "aws_api_gateway_method" "api_methods" {
  for_each      = local.api_endpoints
  rest_api_id   = aws_api_gateway_rest_api.openvas_gw.id
  # Links back to the resource created in step 2
  resource_id   = aws_api_gateway_resource.api_routes[each.value.path].id 
  http_method   = each.value.method
  authorization = "NONE"
}

# 4. Connect the API path to the correct Lambda function
resource "aws_api_gateway_integration" "api_integrations" {
  for_each                = local.api_endpoints
  rest_api_id             = aws_api_gateway_rest_api.openvas_gw.id
  resource_id             = aws_api_gateway_resource.api_routes[each.value.path].id
  http_method             = aws_api_gateway_method.api_methods[each.key].http_method
  integration_http_method = "POST" 
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.openvas_api[each.value.lambda].invoke_arn
}

# 5. Grant API Gateway permission to trigger these Lambdas
resource "aws_lambda_permission" "apigw_invoke_lambdas" {
  for_each      = local.api_endpoints
  statement_id  = "AllowExecutionFromAPIGateway_${each.key}"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.openvas_api[each.value.lambda].function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.openvas_gw.execution_arn}/*/*"
}

# 6. Grant permission for the "Start Scan" Lambda
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

  # CRITICAL UPDATE: This forces Terraform to push a new snapshot to your Stage 
  # whenever you add or change an endpoint in your locals block.
  triggers = {
    redeployment = sha1(jsonencode([aws_api_gateway_integration.api_integrations,
    aws_api_gateway_integration.start_scan_integration.id]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

# 8. Create a Stage (e.g., "v1" or "dev")
resource "aws_api_gateway_stage" "api_stage" {
  deployment_id = aws_api_gateway_deployment.api_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.openvas_gw.id
  stage_name    = "v1"
}

# ==========================================
# /tasks/{task_id}/start Route
# ==========================================

# 1. Create the /{task_id} path under the existing /tasks resource
resource "aws_api_gateway_resource" "task_id" {
  rest_api_id = aws_api_gateway_rest_api.openvas_gw.id
  # This dynamically links to the "tasks" resource created by your loop
  parent_id   = aws_api_gateway_resource.api_routes["tasks"].id 
  path_part   = "{task_id}"
}

# 2. Create the /start path under /{task_id}
resource "aws_api_gateway_resource" "start_scan" {
  rest_api_id = aws_api_gateway_rest_api.openvas_gw.id
  parent_id   = aws_api_gateway_resource.task_id.id
  path_part   = "start"
}

# 3. Attach the POST method
resource "aws_api_gateway_method" "post_start_scan" {
  rest_api_id   = aws_api_gateway_rest_api.openvas_gw.id
  resource_id   = aws_api_gateway_resource.start_scan.id
  http_method   = "POST"
  authorization = "NONE"
}

# 4. Integrate it with your "start_scan" Lambda
resource "aws_api_gateway_integration" "start_scan_integration" {
  rest_api_id             = aws_api_gateway_rest_api.openvas_gw.id
  resource_id             = aws_api_gateway_resource.start_scan.id
  http_method             = aws_api_gateway_method.post_start_scan.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.openvas_api["start_scan"].invoke_arn
}