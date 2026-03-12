resource "aws_db_subnet_group" "rds_postgres_operational_data_warehouse" {
  name       = "rds-postgres-operational-data-warehouse"
  subnet_ids = [aws_subnet.private_a.id, aws_subnet.private_b.id]
}

module "rds_postgres_operational_data_warehouse" {
  source = "terraform-aws-modules/rds/aws"

  identifier = "rds-postgres-operational-data-warehouse"

  engine               = "postgres"
  engine_version       = "17"
  family               = "postgres17"
  major_engine_version = "17"
  instance_class       = "db.t3.micro"

  allocated_storage     = 20
  max_allocated_storage = 100

  multi_az               = false
  db_subnet_group_name   = aws_db_subnet_group.rds_postgres_operational_data_warehouse.name
  vpc_security_group_ids = [module.security_group_rds_postgres_operational_data_warehouse.security_group_id]

  storage_encrypted = true

  backup_retention_period = 1

  skip_final_snapshot = true

  db_name  = "postgres"
  username = "db_admin"
  port     = 5432

  iam_database_authentication_enabled = true
}

module "security_group_rds_postgres_operational_data_warehouse" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 5.0"

  name   = "security-group-rds-postgres-operational-data-warehouse"
  vpc_id = aws_vpc.main.id

  ingress_with_source_security_group_id = [
    {
      from_port                = 5432
      to_port                  = 5432
      protocol                 = "tcp"
      description              = "PostgreSQL access from within VPC"
      source_security_group_id = module.security_group_data_pipeline.security_group_id
    }
  ]
}
