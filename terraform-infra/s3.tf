resource "aws_s3_bucket" "s3_openvas_reports" {
  bucket = "${var.project_name}-openvas-reports"

  tags = {
    Name    = "s3-openvas-reports"
    Project = var.project_name
  }
}

resource "aws_s3_object" "windows_folder" {
  bucket = aws_s3_bucket.s3_openvas_reports.id
  key    = "windows/"
}

resource "aws_s3_object" "linux_folder" {
  bucket = aws_s3_bucket.s3_openvas_reports.id
  key    = "linux/"
}