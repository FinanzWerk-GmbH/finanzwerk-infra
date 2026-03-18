variable "db_username" {
  type        = string
  description = "PostgreSQL IAM username for data pipeline worker"
  default     = "data_pipeline_worker"
}

variable "airflow_dag_repo" {
  type        = string
  description = "Git repo URL for Airflow DAGs (used by git-sync sidecar)"
}
