resource "aws_api_gateway_rest_api" "openvas_gw" {
  name = "OpenVAS-Automation-API"
}

module "api_endpoint" {
  source   = "./modules/api_endpoint"
  for_each = {
    "port-lists" = { lambda = aws_lambda_function.openvas_api["create_port_list"].invoke_arn, method = "POST" }
    "targets"    = { lambda = aws_lambda_function.openvas_api["create_target"].invoke_arn, method = "POST" }
    "tasks"      = { lambda = aws_lambda_function.openvas_api["create_task"].invoke_arn, method = "POST" }
  }
}

resource "aws_api_gateway_resource" "task_id" {
  rest_api_id = aws_api_gateway_rest_api.openvas_gw.id
  parent_id   = aws_api_gateway_rest_api.openvas_gw.root_resource_id
  path_part   = "{task_id}"
}

resource "aws_api_gateway_resource" "start" {
  rest_api_id = aws_api_gateway_rest_api.openvas_gw.id
  parent_id   = aws_api_gateway_resource.task_id.id
  path_part   = "start"
}

resource "aws_api_gateway_method" "start_post" {
  rest_api_id   = aws_api_gateway_rest_api.openvas_gw.id
  resource_id   = aws_api_gateway_resource.start.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "start_integration" {
  rest_api_id = aws_api_gateway_rest_api.openvas_gw.id
  resource_id = aws_api_gateway_resource.start.id
  http_method = aws_api_gateway_method.start_post.http_method
  type        = "AWS_PROXY"
  uri         = aws_lambda_function.openvas_api["start_scan"].invoke_arn
}