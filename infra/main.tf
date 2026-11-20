provider "aws" {
  region = "us-east-1"
}

provider "aws" {
  alias  = "replica"
  region = "us-west-2"
}

resource "random_id" "suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "datos" {
  bucket = "galileo-datos-${random_id.suffix.hex}"
}

resource "aws_s3_bucket_versioning" "datos" {
  bucket = aws_s3_bucket.datos.id
  versioning_configuration {
    status = "Enabled"
  }
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

resource "aws_s3_bucket_lifecycle_configuration" "datos" {
  bucket = aws_s3_bucket.datos.id
  rule {
    id     = "expirar-objetos"
    status = "Enabled"
    expiration {
      days = 365
    }
    # CKV_AWS_300: aborta uploads multipart incompletos
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# CKV2_AWS_62: notificaciones de eventos (EventBridge)
resource "aws_s3_bucket_notification" "datos" {
  bucket      = aws_s3_bucket.datos.id
  eventbridge = true
}

resource "aws_s3_bucket" "logs" {
  bucket = "galileo-logs-${random_id.suffix.hex}"
}

resource "aws_s3_bucket_versioning" "logs" {
  bucket = aws_s3_bucket.logs.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.s3.arn
    }
  }
}

resource "aws_s3_bucket_public_access_block" "logs" {
  bucket                  = aws_s3_bucket.logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id
  rule {
    id     = "expirar-logs"
    status = "Enabled"
    expiration {
      days = 365
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_s3_bucket_notification" "logs" {
  bucket      = aws_s3_bucket.logs.id
  eventbridge = true
}

# Access logging del bucket datos hacia el bucket logs
resource "aws_s3_bucket_logging" "datos" {
  bucket        = aws_s3_bucket.datos.id
  target_bucket = aws_s3_bucket.logs.id
  target_prefix = "log/"
}

resource "aws_kms_key" "s3" {
  description             = "KMS para buckets S3"
  deletion_window_in_days = 7
  enable_key_rotation     = true
}

# CKV2_AWS_64: policy explícita de la KMS key
resource "aws_kms_key_policy" "s3" {
  key_id = aws_kms_key.s3.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "Enable IAM User Permissions"
        Effect    = "Allow"
        Principal = { AWS = "*" }
        Action    = "kms:*"
        Resource  = "*"
      }
    ]
  })
}

resource "aws_kms_key" "rds" {
  description             = "KMS para RDS"
  deletion_window_in_days = 7
  enable_key_rotation     = true
}

resource "aws_kms_key_policy" "rds" {
  key_id = aws_kms_key.rds.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "Enable IAM User Permissions"
        Effect    = "Allow"
        Principal = { AWS = "*" }
        Action    = "kms:*"
        Resource  = "*"
      }
    ]
  })
}

resource "aws_security_group" "web" {
  name        = "web-sg"
  description = "Permite SSH solo desde red privada"

  ingress {
    description = "SSH desde red privada"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.10.0.0/24"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_iam_role" "rds_monitoring" {
  name = "rds-monitoring-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Principal = { Service = "monitoring.rds.amazonaws.com" }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "rds_monitoring_attach" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

resource "aws_db_instance" "db" {
  identifier        = "galileo-db"
  engine            = "postgres"
  instance_class    = "db.t3.micro"
  allocated_storage = 20
  username          = "admin"
  password          = "cambiame-en-secrets"

  # Backups y disponibilidad
  backup_retention_period = 7
  multi_az                = true

  # Cifrado en reposo (CKV_AWS_16)
  storage_encrypted = true
  kms_key_id        = aws_kms_key.rds.arn

  # Protección contra borrado (CKV_AWS_293)
  deletion_protection = true

  # Actualizaciones automáticas y auth IAM
  auto_minor_version_upgrade          = true
  iam_database_authentication_enabled = true

  # Monitoring y Performance Insights
  monitoring_interval             = 60
  monitoring_role_arn             = aws_iam_role.rds_monitoring.arn
  performance_insights_enabled    = true
  performance_insights_kms_key_id = aws_kms_key.rds.arn   # CKV_AWS_354

  # Logs exportados
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  # Tags y snapshots
  copy_tags_to_snapshot = true
  publicly_accessible   = false
}

resource "aws_iam_role" "app" {
  name = "app-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Principal = { Service = "ec2.amazonaws.com" }
      }
    ]
  })
}

resource "aws_iam_instance_profile" "app" {
  name = "app-instance-profile"
  role = aws_iam_role.app.name
}

resource "aws_instance" "app" {
  ami                         = "ami-0c02fb55956c7d316"
  instance_type               = "t3.micro"
  vpc_security_group_ids      = [aws_security_group.web.id]
  iam_instance_profile        = aws_iam_instance_profile.app.name   # CKV2_AWS_41
  ebs_optimized               = true                                 # CKV_AWS_135
  monitoring                  = true                                 # CKV_AWS_126

  metadata_options {                                                 # CKV_AWS_79
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  root_block_device {                                                # CKV_AWS_8
    encrypted = true
  }

  tags = { Name = "app-demo" }
}

resource "aws_iam_role" "replication" {
  name = "s3-replication-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Principal = { Service = "s3.amazonaws.com" }
      }
    ]
  })
}

resource "aws_s3_bucket" "datos_replica" {
  provider = aws.replica
  bucket   = "galileo-datos-replica-${random_id.suffix.hex}"
}

resource "aws_s3_bucket_versioning" "datos_replica" {
  provider = aws.replica
  bucket   = aws_s3_bucket.datos_replica.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_replication_configuration" "datos" {
  bucket = aws_s3_bucket.datos.id
  role   = aws_iam_role.replication.arn

  rule {
    id     = "replicar-todo-datos"
    status = "Enabled"
    destination {
      bucket        = aws_s3_bucket.datos_replica.arn
      storage_class = "STANDARD"
    }
  }
}

resource "aws_s3_bucket" "logs_replica" {
  provider = aws.replica
  bucket   = "galileo-logs-replica-${random_id.suffix.hex}"
}

resource "aws_s3_bucket_versioning" "logs_replica" {
  provider = aws.replica
  bucket   = aws_s3_bucket.logs_replica.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_replication_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id
  role   = aws_iam_role.replication.arn

  rule {
    id     = "replicar-todo-logs"
    status = "Enabled"
    destination {
      bucket        = aws_s3_bucket.logs_replica.arn
      storage_class = "STANDARD"
    }
  }
}