# outputs.tf

# This Terraform configuration defines outputs for the EC2 instances created in the infrastructure.
# It provides the instance IDs for the Ubuntu and Windows EC2 instances, as well as a list of instances that are ready for SSM management. The Amazon Linux instance output is currently commented out but can be included if needed in the future.
output "ec2_instances" {
  value = {
    # amazon_linux = aws_instance.linux_amazon.id
    ubuntu  = aws_instance.linux_ubuntu.id
    windows = aws_instance.windows.id
    openvas = aws_instance.openvas.id
  }
}

output "api_base_url" {
  description = "The base URL for your OpenVAS API"
  value       = aws_api_gateway_stage.api_stage.invoke_url
}
