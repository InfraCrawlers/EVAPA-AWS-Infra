resource "aws_s3_bucket" "s3_openvas_reports" {
  bucket = "${var.project_name}-openvas-reports"

  tags = {
    Name    = "s3-openvas-reports"
    Project = var.project_name
  }
}

resource "aws_s3_bucket" "ssm_ansible_bucket" {
  bucket = "${var.project_name}-ssm-ansible-bucket"

  tags = {
    Name    = "${var.project_name}-ssm-ansible-bucket"
    Project = var.project_name
  }
}


# Recommended: block public access
resource "aws_s3_bucket_public_access_block" "ssm_bucket_block" {
  bucket = aws_s3_bucket.ssm_ansible_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "ssm_bucket_versioning" {
  bucket = aws_s3_bucket.ssm_ansible_bucket.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_object" "windows_folder" {
  bucket = aws_s3_bucket.s3_openvas_reports.id
  key    = "openvas-reports/"
}