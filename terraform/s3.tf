resource "aws_s3_bucket" "photos" {
  bucket = "${var.app_name}-pet-photos-${var.environment}"

  tags = {
    Name = "${var.app_name}-pet-photos"
  }
}

resource "aws_s3_bucket_acl" "photos" {
  bucket = aws_s3_bucket.photos.id
  acl    = "public-read"
}
