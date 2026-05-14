resource "kubernetes_job_v1" "create_airflow_db" {
  depends_on = [kubernetes_manifest.postgres_cluster]
  metadata {
    name      = "create-airflow-db"
    namespace = var.postgres_namespace
  }
  spec {
    template {
      metadata {}
      spec {
        restart_policy = "OnFailure"
        container {
          name  = "psql"
          image = "ghcr.io/cloudnative-pg/postgresql:16"
          command = [
            "/bin/sh", "-c",
            "psql postgresql://${var.postgres_finanzwerk_owner_username}:$OWNER_PASSWORD@postgres-rw:5432/postgres -c 'CREATE DATABASE airflow OWNER ${var.postgres_finanzwerk_owner_username}' || true"
          ]
          env {
            name = "OWNER_PASSWORD"
            value_from {
              secret_key_ref {
                name = "postgres-credentials"
                key  = "password"
              }
            }
          }
        }
      }
    }
  }
  timeouts {
    create = "2m"
  }
}

resource "helm_release" "airflow" {
  depends_on = [
    kubernetes_namespace_v1.airflow_namespace,
    kubernetes_job_v1.create_airflow_db,
  ]
  name       = "airflow"
  repository = "https://airflow.apache.org"
  chart      = "airflow"
  namespace  = var.airflow_namespace

  values = [<<-EOT
    executor: KubernetesExecutor

    postgresql:
      enabled: false

    data:
      metadataConnection:
        user: ${var.postgres_finanzwerk_owner_username}
        pass: ${var.postgres_finanzwerk_owner_password}
        host: postgres-rw.${var.postgres_namespace}.svc.cluster.local
        port: "5432"
        db: airflow
        protocol: postgresql+psycopg2

    webserver:
      defaultUser:
        enabled: true
        username: admin
        password: admin
        email: admin@finanzwerk.local
        role: Admin
      resources:
        requests:
          memory: 512Mi
          cpu: 250m

    scheduler:
      resources:
        requests:
          memory: 512Mi
          cpu: 250m
      extraVolumeMounts:
        - name: dbt-sync
          mountPath: /opt/airflow/dbt
      extraContainers:
        - name: git-sync-dbt
          image: registry.k8s.io/git-sync/git-sync:v4.2.0
          args:
            - --repo=${var.airflow_dbt_git_repo}
            - --branch=main
            - --root=/opt/airflow/dbt
            - --dest=finanzwerk_dbt
            - --period=60s
          volumeMounts:
            - name: dbt-sync
              mountPath: /opt/airflow/dbt

    triggerer:
      enabled: true
      resources:
        requests:
          memory: 256Mi
          cpu: 100m

    workers:
      replicas: 0

    redis:
      enabled: false

    dags:
      gitSync:
        enabled: true
        repo: ${var.airflow_git_repo}
        branch: main
        subPath: dags
        period: 60s
        depth: 1

    ingress:
      web:
        enabled: true
        ingressClassName: ${var.nginx_ingress_classname}
        hosts:
          - name: ${var.airflow_ingress_host}

    connections:
      - id: minio_conn
        type: aws
        login: ${var.minio_root_username}
        password: ${var.minio_root_password}
        extra: '{"endpoint_url": "http://minio.${var.minio_namespace}.svc.cluster.local:9000"}'
      - id: finanzwerk_db
        type: postgres
        host: postgres-rw.${var.postgres_namespace}.svc.cluster.local
        port: 5432
        schema: ${var.postgres_finanzwerk_db}
        login: ${var.postgres_finanzwerk_readwrite_username}
        password: ${var.postgres_finanzwerk_readwrite_password}

    extraVolumes:
      - name: dbt-sync
        emptyDir: {}

    env:
      - name: _PIP_ADDITIONAL_REQUIREMENTS
        value: "astronomer-cosmos[dbt-postgres] soda-core-postgres dbt-postgres deltalake pandas pyarrow great-expectations apache-airflow-providers-cncf-kubernetes mlflow"
      - name: MLFLOW_TRACKING_URI
        value: http://mlflow.${kubernetes_namespace_v1.data_tools_namespace.metadata[0].name}.svc.cluster.local:5000
      - name: PYTHONPATH
        value: /opt/airflow/dags/repo
      - name: MINIO_ENDPOINT
        value: http://minio.${var.minio_namespace}.svc.cluster.local:9000
      - name: MINIO_ACCESS_KEY
        value: ${var.minio_root_username}
      - name: MINIO_SECRET_KEY
        value: ${var.minio_root_password}
      - name: DB_HOST
        value: postgres-rw.${var.postgres_namespace}.svc.cluster.local
      - name: DB_PORT
        value: "5432"
      - name: DB_NAME
        value: ${var.postgres_finanzwerk_db}
      - name: DB_USER
        value: ${var.postgres_finanzwerk_readwrite_username}
      - name: DB_PASSWORD
        value: ${var.postgres_finanzwerk_readwrite_password}
      - name: VENDOR_API_URL
        value: http://mock-vendor-api.${var.airflow_namespace}.svc.cluster.local:8000
    EOT
  ]
}
