variable "minikube_storage_class" {
  default = "standard"
}


# namespaces
variable "nginx_ingress_classname" {
  default = "nginx"
}
variable "data_core_namespace" {
  default = "data-core"
}
variable "postgres_namespace" {
  default = "postgres"
}
variable "minio_namespace" {
  default = "minio"
}
variable "vault_namespace" {
  default = "vault"
}


# minio
variable "minio_root_username" {
  default = "admin"
}
variable "minio_root_password" {
  default = "admin_password"
}
variable "minio_api_endpoint" {
  default = "minio:9000"
}
variable "minio_console_ingress_host" {
  default = "minio-console.127.0.0.1.nip.io"
}
variable "minio_initial_buckets" {
  type    = list(string)
  default = ["finanzwerk-raw", "finanzwerk-processed", "finanzwerk-scripts", "backups"]
}

# Postgres
variable "postgres_finanzwerk_db" {
  default = "finanzwerk"
}
variable "postgres_finanzwerk_owner_username" {
  default = "admin"
}
variable "postgres_finanzwerk_owner_password" {
  default = "admin_password"
}
variable "postgres_finanzwerk_readwrite_username" {
  default = "readwrite"
}
variable "postgres_finanzwerk_readwrite_password" {
  default = "readwrite_password"
}
variable "postgres_finanzwerk_readonly_username" {
  default = "readonly"
}
variable "postgres_finanzwerk_readonly_password" {
  default = "readonly_password"
}
variable "postgres_debezium_password" {
  default = "debezium_password"
}

variable "clickhouse_admin_password" {
  default = "clickhouse_admin"
}
variable "keycloak_admin_password" {
  default = "keycloak_admin"
}
variable "postgres_backup_s3_destination" {
  default = "s3://backups/postgres"
}

# vault
variable "vault_ingress_host" {
  default = "vault.127.0.0.1.nip.io"
}
variable "vault_endpoint" {
  default = "vault:8200"
}

# airflow
variable "airflow_namespace" {
  default = "airflow"
}
variable "airflow_git_repo" {
  default = "https://github.com/your-org/finanzwerk-airflow"
}
variable "airflow_dbt_git_repo" {
  default = "https://github.com/your-org/finanzwerk-dbt"
}
variable "airflow_ingress_host" {
  default = "airflow.127.0.0.1.nip.io"
}
