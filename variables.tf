
variable "project_name" {
  description = "Name of the CloudNexus project"
  type        = string
  default     = "cloudnexus"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "dev"
}
