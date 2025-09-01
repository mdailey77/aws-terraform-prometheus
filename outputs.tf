output "registry_id" {
  value       = aws_ecr_repository.ecr_repo.registry_id
  description = "Registry ID"
}

output "repository_name" {
  value       = aws_ecr_repository.ecr_repo.name
  description = "Name of first repository created"
}

output "repository_url" {
  value       = aws_ecr_repository.ecr_repo.repository_url
  description = "URL of first repository created"
}

output "repository_arn" {
  value       = aws_ecr_repository.ecr_repo.arn
  description = "URL of first repository created"
}