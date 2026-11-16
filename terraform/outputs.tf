output "api_url" {
  description = "Put this in frontend/.env as VITE_API_URL"
  value       = aws_apigatewayv2_api.http.api_endpoint
}



output "processed_bucket" {
  value = aws_s3_bucket.processed.id
}

output "dynamodb_table" {
  value = aws_dynamodb_table.files.name
}
