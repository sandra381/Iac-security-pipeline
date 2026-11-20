provider "aws" {
 region = "us-east-1"
}
resource "aws_s3_bucket" "datos" {
 bucket = "galileo-demo-datos"
}

resource "aws_kms_key" "s3" {
  description             = "KMS para bucket datos"
  deletion_window_in_days = 7
  enable_key_rotation     = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "datos" {
  bucket = aws_s3_bucket.datos.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.s3.arn
    }
  }
}
resource "aws_s3_bucket_public_access_block" "datos" {
  bucket                  = aws_s3_bucket.datos.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "datos" {
  bucket = aws_s3_bucket.datos.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_security_group" "web" {
  name        = "web"
  description = "Acceso al servidor web"

  ingress {
    description = "SSH solo desde la VPN"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.10.0.0/24"]
  }
}
resource "aws_db_instance" "db" {
  # ... lo que ya tienes ...

  auto_minor_version_upgrade            = true           # CKV_AWS_226
  performance_insights_enabled          = true           # CKV_AWS_353
  iam_database_authentication_enabled   = true           # CKV_AWS_161
  multi_az                              = true           # CKV_AWS_157
  monitoring_interval                   = 1              # CKV_AWS_118
  monitoring_role_arn                   = aws_iam_role.rds_monitoring.arn
  copy_tags_to_snapshot                 = true           # CKV2_AWS_60
  backup_retention_period               = 7              # CKV2_CURSO_1
  enabled_cloudwatch_logs_exports       = ["postgresql", "upgrade"]  # CKV_AWS_129, CKV2_AWS_30
}

# Necesario para el monitoring_interval
resource "aws_iam_role" "rds_monitoring" {
  name = "rds-monitoring-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "monitoring.rds.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "rds_monitoring_attach" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}