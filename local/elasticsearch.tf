resource "helm_release" "elasticsearch" {
  name             = "elasticsearch"
  repository       = "https://charts.bitnami.com/bitnami"
  chart            = "elasticsearch"
  version          = "21.3.14"
  namespace        = kubernetes_namespace_v1.governance_namespace.metadata[0].name
  create_namespace = false
  wait             = false
  timeout          = 600

  values = [<<-EOT
    master:
      replicaCount: 1
      masterOnly: false
      heapSize: 512m
    coordinating:
      replicaCount: 0
    data:
      replicaCount: 0
    ingest:
      enabled: false
    global:
      kibanaEnabled: false
    resources:
      requests:
        memory: 768Mi
        cpu: 250m
      limits:
        memory: 1Gi
        cpu: 1000m
    persistence:
      size: 5Gi
    security:
      enabled: false
  EOT
  ]
}
