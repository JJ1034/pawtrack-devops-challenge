resource "aws_db_subnet_group" "main" {
  name       = "${var.app_name}-db-subnet"
  subnet_ids = aws_subnet.private[*].id

  tags = {
    Name = "${var.app_name}-db-subnet"
  }
}

resource "aws_db_instance" "main" {
  identifier     = "${var.app_name}-db"
  engine         = "postgres"
  engine_version = "15.4"
  instance_class = "db.t3.micro"

  allocated_storage     = 20
  max_allocated_storage = 100
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = "pawtrack"
  username = var.db_username
  password = random_password.db.result

  parameter_group_name = "default.postgres15"

  multi_az            = true
  publicly_accessible = false

  # Allow IAM database authentication. We don't currently issue IAM
  # tokens, but flipping this on costs nothing and lets us migrate
  # later without a maintenance window.
  iam_database_authentication_enabled = true

  vpc_security_group_ids = [aws_security_group.rds.id]
  db_subnet_group_name   = aws_db_subnet_group.main.name

  backup_retention_period = 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "mon:04:00-mon:05:00"

  auto_minor_version_upgrade = true

  # Performance Insights left off until we have a project KMS CMK.
  # Enabling it without one stores captured query data with the
  # AWS-managed key, which is a real risk because PI can record
  # parameter values from queries.
  performance_insights_enabled = false

  deletion_protection       = true
  skip_final_snapshot       = false
  final_snapshot_identifier = "${var.app_name}-db-final-${formatdate("YYYYMMDDhhmmss", timestamp())}"

  # `password` and `final_snapshot_identifier` change shape on every plan;
  # we don't want a plan to look noisy, and the password is rotated via
  # Secrets Manager not Terraform.
  lifecycle {
    ignore_changes = [
      password,
      final_snapshot_identifier,
    ]
  }

  tags = {
    Name = "${var.app_name}-db"
  }
}
