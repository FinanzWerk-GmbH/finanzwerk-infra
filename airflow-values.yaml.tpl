executor: KubernetesExecutor

workers:
  serviceAccount:
    create: false
    name: ${worker_sa_name}

scheduler:
  replicas: 1

webserver:
  replicas: 1
  service:
    type: ClusterIP

ingress:
  enabled: false

# Use external RDS — disable the bundled PostgreSQL
postgresql:
  enabled: false

migrateDatabaseJob:
  enabled: true
  useHelmHooks: false

createUserJob:
  useHelmHooks: false

data:
  metadataSecretName: airflow-metadata-secret

fernetKeySecretName: airflow-fernet-key

logs:
  persistence:
    enabled: false

triggerer:
  persistence:
    enabled: false

dags:
  gitSync:
    enabled: false
