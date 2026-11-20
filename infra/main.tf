# =====================================================================
# Providers
# =====================================================================
provider "aws" {
  region = "us-east-1"
}

provider "aws" {
  alias  = "replica"
  region = "us-west-2"
}

# =====================================================================
# Random para nombres y password
# =====================================================================
resource "random_id" "suffix" {
  byte_length = 4
}

resource "random_password" "db" {
  length  = 32
  special = true
}

# =====================================================================
# KMS (región principal)
# =====================================================================
resource "aws_kms_key" "s3" {
  description             = "KMS para buckets S3"
  deletion_window_in_days = 7
  enable_key_rotation     = true
}

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

# =====================================================================
# KMS (región réplica)
# =====================================================================
resource "aws_kms_key" "s3_replica" {
  provider                = aws.replica
  description             = "KMS para buckets S3 réplica"
  deletion_window_in_days = 7
  enable_key_rotation     = true
}

resource "aws_kms_key_policy" "s3_replica" {
  provider = aws.replica
  key_id   = aws_kms_key.s3_replica.id
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

# =====================================================================
# Bucket S3 "datos" (principal)
# =====================================================================
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
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_s3_bucket_notification" "datos" {
  bucket      = aws_s3_bucket.datos.id
  eventbridge = true
}

# =====================================================================
# Bucket S3 "logs" (principal)
# =====================================================================
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

resource "aws_s3_bucket_logging" "datos" {
  bucket        = aws_s3_bucket.datos.id
  target_bucket = aws_s3_bucket.logs.id
  target_prefix = "log/"
}

# =====================================================================
# Security Group (SSH restringido + egress limitado)
# =====================================================================
resource "aws_security_group" "web" {
  name        = "web-sg"
  description = "SSH desde red privada y HTTPS de salida"

  ingress {
    description = "SSH desde red privada"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.10.0.0/24"]
  }

  egress {
    description = "HTTPS de salida"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# =====================================================================
# RDS (endurecido + query logging + encryption in transit)
# =====================================================================
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

# CKV2_AWS_30 + CKV2_AWS_69: logs + SSL obligatorio
resource "aws_db_parameter_group" "postgres" {
  name   = "galileo-pg"
  family = "postgres14"

  parameter {
    name  = "log_statement"
    value = "all"
  }

  # CKV2_AWS_69: fuerza SSL en todas las conexiones
  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }
}

resource "aws_db_instance" "db" {
  identifier           = "galileo-db"
  engine               = "postgres"
  engine_version       = "14"
  instance_class       = "db.t3.micro"
  allocated_storage    = 20
  username             = "admin"
  password             = random_password.db.result
  parameter_group_name = aws_db_parameter_group.postgres.name

  backup_retention_period = 7
  multi_az                = true
  storage_encrypted       = true
  kms_key_id              = aws_kms_key.rds.arn
  deletion_protection     = true

  auto_minor_version_upgrade          = true
  iam_database_authentication_enabled = true

  monitoring_interval             = 60
  monitoring_role_arn             = aws_iam_role.rds_monitoring.arn
  performance_insights_enabled    = true
  performance_insights_kms_key_id = aws_kms_key.rds.arn

  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]
  copy_tags_to_snapshot           = true
  publicly_accessible             = false
}

# =====================================================================
# EC2 (endurecido con rol IAM)
# =====================================================================
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
  ami                    = "ami-0c02fb55956c7d316"
  instance_type          = "t3.micro"
  vpc_security_group_ids = [aws_security_group.web.id]
  iam_instance_profile   = aws_iam_instance_profile.app.name
  ebs_optimized          = true
  monitoring             = true

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  root_block_device {
    encrypted = true
  }

  tags = { Name = "app-demo" }
}

# =====================================================================
# Replicación cross-region
# =====================================================================
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

# ---- Bucket datos_replica (us-west-2) ----
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

resource "aws_s3_bucket_server_side_encryption_configuration" "datos_replica" {
  provider = aws.replica
  bucket   = aws_s3_bucket.datos_replica.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.s3_replica.arn
    }
  }
}

resource "aws_s3_bucket_public_access_block" "datos_replica" {
  provider                = aws.replica
  bucket                  = aws_s3_bucket.datos_replica.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "datos_replica" {
  provider = aws.replica
  bucket   = aws_s3_bucket.datos_replica.id
  rule {
    id     = "expirar-datos-replica"
    status = "Enabled"
    expiration {
      days = 365
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_s3_bucket_notification" "datos_replica" {
  provider    = aws.replica
  bucket      = aws_s3_bucket.datos_replica.id
  eventbridge = true
}

# ---- Bucket logs_replica (us-west-2) ----
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

resource "aws_s3_bucket_server_side_encryption_configuration" "logs_replica" {
  provider = aws.replica
  bucket   = aws_s3_bucket.logs_replica.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.s3_replica.arn
    }
  }
}

resource "aws_s3_bucket_public_access_block" "logs_replica" {
  provider                = aws.replica
  bucket                  = aws_s3_bucket.logs_replica.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "logs_replica" {
  provider = aws.replica
  bucket   = aws_s3_bucket.logs_replica.id
  rule {
    id     = "expirar-logs-replica"
    status = "Enabled"
    expiration {
      days = 365
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_s3_bucket_notification" "logs_replica" {
  provider    = aws.replica
  bucket      = aws_s3_bucket.logs_replica.id
  eventbridge = true
}

# ---- Access logging de los buckets réplica ----
resource "aws_s3_bucket_logging" "datos_replica" {
  provider      = aws.replica
  bucket        = aws_s3_bucket.datos_replica.id
  target_bucket = aws_s3_bucket.logs_replica.id
  target_prefix = "log-datos/"
}

resource "aws_s3_bucket_logging" "logs_replica" {
  provider      = aws.replica
  bucket        = aws_s3_bucket.logs_replica.id
  target_bucket = aws_s3_bucket.logs_replica.id
  target_prefix = "log-logs/"
}

# ---- Configuración de replicación ----
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