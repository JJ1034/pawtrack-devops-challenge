resource "random_password" "db" {
  length  = 32
  special = true
  # RDS Postgres rejects '/', '@', '"' and ' ' in master passwords
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_secretsmanager_secret" "db" {
  name                    = "${var.app_name}/${var.environment}/db"
  description             = "Master credentials for the ${var.app_name} ${var.environment} database"
  recovery_window_in_days = 7
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id
  secret_string = jsonencode({
    username = var.db_username
    password = random_password.db.result
    host     = aws_db_instance.main.address
    port     = aws_db_instance.main.port
    dbname   = aws_db_instance.main.db_name
  })
}
