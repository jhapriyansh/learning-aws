provider "aws" {
	region = "us-east-1"
	access_key = "test"
  	secret_key = "test"
	skip_credentials_validation = true
  	skip_metadata_api_check     = true
  	skip_requesting_account_id  = true

  	endpoints {
    s3 = "http://10.99.24.68:4566"
  }
}

resource "aws_s3_bucket" "my_bucket" {
	bucket = "nextwork-unique-bucket-priyanshu-6969"
	tags = {
		Environment = "Dev"
	}
}

resource "aws_s3_bucket_public_access_block" "my_bucket_public_access_block" {
	bucket = aws_s3_bucket.my_bucket.id

	block_public_acls	= true
	ignore_public_acls	= true
	block_public_policy	= true
	restrict_public_buckets = true
}

resource "aws_s3_object" "image" {
	bucket = aws_s3_bucket.my_bucket.id
	key = "image.jpg"
	source = "test.jpg"
}
