
output "bucket_name" {
  description = "Name of the CloudNexus S3 bucket"
  value       = aws_s3_bucket.app_storage.bucket
}
