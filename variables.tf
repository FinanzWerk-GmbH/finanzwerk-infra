variable "db_username" {
  type        = string
  description = "PostgreSQL IAM username for data pipeline worker"
  default     = "data_pipeline_worker"
}
