# DevSecOps Module 3 hands-on — deliberately bad Terraform for Checkov practice
# DO NOT use this file as a template for real infrastructure.

resource "aws_security_group" "web" {
  name        = "web-bad"
  description = "Bad SG — wide open"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]   # SSH open to the internet
  }

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]   # All ports open to the internet
  }
}

resource "aws_s3_bucket" "data" {
  bucket = "prod-customer-data"
}

resource "aws_s3_bucket_public_access_block" "data" {
  bucket                  = aws_s3_bucket.data.id
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_db_instance" "orders" {
  identifier            = "orders"
  engine                = "postgres"
  instance_class        = "db.t3.medium"
  allocated_storage     = 20
  username              = "admin"
  password              = "Password123!"   # Hard-coded password
  publicly_accessible   = true             # Database open to internet
  storage_encrypted     = false            # Storage not encrypted
  skip_final_snapshot   = true
}
