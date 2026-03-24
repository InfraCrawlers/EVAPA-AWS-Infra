resource "aws_lambda_function" "openvas_api" {
  for_each      = toset(["create_port_list", "create_target", "create_task", "start_scan"])
  function_name = "openvas_${each.key}"
  role          = aws_iam_role.lambda_exec.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.9"
  layers        = [aws_lambda_layer_version.gvm_layer.arn]
  timeout       = 30

  filename      = "${each.key}.zip" 

  vpc_config {
    subnet_ids         = data.aws_subnets.private.ids
    security_group_ids = [aws_security_group.lambda_sg.id]
  }

  environment {
    variables = var.common_env_vars
  }
}

resource "aws_iam_role" "lambda_exec" {
  name = "openvas_api_lambda_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_vpc_access" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_lambda_layer_version" "gvm_layer" {
  filename   = "gvm_layer.zip"
  layer_name = "python_gvm_library"
  compatible_runtimes = ["python3.9"]
}