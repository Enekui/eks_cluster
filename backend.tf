terraform {
  backend "s3" {
      bucket = "terraform-aws-s3"
      key    = "eks.tfstate"
      region = "us-east-2"
      dynamodb_table = "terraform-state-locking"
  } 
}
