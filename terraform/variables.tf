variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Deployment environment (dev/staging/production)"
  type        = string
  default     = "production"
}

variable "app_name" {
  description = "Application name"
  type        = string
  default     = "pawtrack"
}

variable "db_username" {
  description = "Database master username"
  type        = string
  default     = "pawtrack_admin"
}

variable "container_port" {
  description = "Port the container listens on"
  type        = number
  default     = 8080
}

variable "container_cpu" {
  description = "CPU units for the container"
  type        = number
  default     = 256
}

variable "container_memory" {
  description = "Memory for the container in MiB"
  type        = number
  default     = 512
}

variable "image_tag" {
  description = "Container image tag to deploy. Set by CI to the immutable git SHA."
  type        = string
  default     = "latest"
}

variable "log_retention_days" {
  description = "CloudWatch log retention for the API task"
  type        = number
  default     = 30
}

variable "desired_count" {
  description = "Desired number of ECS tasks"
  type        = number
  default     = 2
}

variable "certificate_arn" {
  description = "ACM certificate ARN for the ALB HTTPS listener. When empty, only HTTP is served. Production should set this and let the HTTP listener redirect."
  type        = string
  default     = ""
}
