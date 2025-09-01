variable "region" {
  type        = string
  default     = ""
  description = "The aws region where the resources will be deployed."
}

variable "ecr_repo_name" {
  type        = string
  default     = ""
  description = "The name of the Elastic Container Registry repository"
}

variable "image_tag_mutability" {
  type        = string
  default     = "IMMUTABLE"
  description = "The tag mutability setting for the repository. Must be one of: `MUTABLE` or `IMMUTABLE`"
}

variable "scan_images_on_push" {
  type        = bool
  description = "Indicates whether images are scanned after being pushed to the repository (Deprecated)"
  default     = true
}

variable "ecr_cluster_name" {
  type        = string
  default     = ""
  description = "The name of the Elastic Container Service cluster"
}

variable "ecs_service_name" {
  type        = string
  default     = ""
  description = "The name of the service running in the ECS cluster"
}

variable "ecs_container_name" {
  type        = string
  default     = ""
  description = "The name of the service running in the ECS cluster"
}

variable "ecs_container_port" {
  type        = number
  description = "The ports used by the container in the ECS service"
}

variable "ecs_namespace" {
  type        = string
  default     = ""
  description = "The namespace where the ECS cluster and service are located"
}

variable "alb_name" {
  type        = string
  default     = ""
  description = "The ALB for the ECS cluster"
}

variable "vpc_name" {
  type        = string
  default     = ""
  description = "The VPC for the ECS cluster"
}