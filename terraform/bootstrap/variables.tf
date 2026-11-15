variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "bucket_name" {
  description = "Name of the S3 bucket used as the Terraform remote state backend for the togglemaster environment (state key stays togglemaster/fase03/... for continuity — Fase04 deliberately shares it rather than starting a fresh state)."
  type        = string
  default     = "togglemaster-tfstate-108101918154"
}
