resource "aws_db_subnet_group" "main" {
  name       = "${var.app_name}-db-subnet"
  subnet_ids = [aws_subnet.private.id]

  tags = {
    Name = "${var.app_name}-db-subnet"
  }
}

resource "aws_db_instance" "main" {
  identifier           = "${var.app_name}-db"
  engine               = "postgres"
  engine_version       = "15.4"
  instance_class       = "db.t3.micro"
  allocated_storage    = 20
  storage_type         = "gp3"
  db_name              = "pawtrack"
  username             = var.db_username
  password             = var.db_password
  parameter_group_name = "default.postgres15"
  skip_final_snapshot  = true

  vpc_security_group_ids = [aws_security_group.rds.id]
  db_subnet_group_name   = aws_db_subnet_group.main.name

  tags = {
    Name = "${var.app_name}-db"
  }
}
