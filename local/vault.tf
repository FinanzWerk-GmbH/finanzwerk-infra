resource "helm_release" "vault" {
  depends_on = [kubernetes_namespace_v1.vault_namespace]
  name       = "vault"
  repository = "https://helm.releases.hashicorp.com"
  chart      = "vault"
  namespace  = var.vault_namespace
  set = [
    {
      name  = "server.affinity"
      value = ""
    },
    {
      name  = "injector.affinity"
      value = ""
    },
    {
      name  = "server.dataStorage.size"
      value = "2Gi"
    },
    {
      name  = "ui.enabled"
      value = "true"
    },
    {
      name  = "server.ingress.enabled"
      value = "true"
    },
    {
      name  = "server.ingress.ingressClassName"
      value = var.nginx_ingress_classname
    },
    {
      name  = "server.ingress.hosts[0].host"
      value = var.vault_ingress_host
    }
  ]
}

resource "kubernetes_job_v1" "vault_init" {
  depends_on = [helm_release.vault, kubernetes_secret_v1.vault_init_keys]

  metadata {
    name      = "vault-init"
    namespace = var.vault_namespace
  }
  spec {
    template {
      metadata {}
      spec {
        service_account_name = "vault-init"
        restart_policy       = "OnFailure"
        container {
          name  = "vault-init"
          image = "hashicorp/vault:1.21.2"
          command = [
            "/bin/sh", "-c",
            <<-EOT
              # Install dependencies
              apk add --no-cache curl jq

              # Install kubectl
              curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
              chmod +x kubectl && mv kubectl /usr/local/bin/

              # Wait for Vault to be reachable
              until curl -s http://vault:8200/v1/sys/health | grep -q "initialized"; do
                echo "Waiting for Vault..."
                sleep 3
              done

              INIT_STATUS=$(curl -s http://vault:8200/v1/sys/health | jq -r '.initialized')

              if [ "$INIT_STATUS" = "false" ]; then
                echo "Initializing Vault..."
                curl -s -X PUT http://vault:8200/v1/sys/init \
                  -d '{"secret_shares":1,"secret_threshold":1}' > /tmp/init.json

                cat /tmp/init.json

                UNSEAL_KEY=$(jq -r '.keys_base64[0]' /tmp/init.json)
                ROOT_TOKEN=$(jq -r '.root_token' /tmp/init.json)

                echo "Saving keys..."
                kubectl patch secret vault-init-keys \
                  -n ${var.vault_namespace} \
                  -p "{\"data\":{\"unseal-key\":\"$(echo -n $UNSEAL_KEY | base64)\",\"root-token\":\"$(echo -n $ROOT_TOKEN | base64)\"}}"
              else
                echo "Vault already initialized, retrieving saved keys..."
                UNSEAL_KEY=$(kubectl get secret vault-init-keys -n ${var.vault_namespace} -o jsonpath='{.data.unseal-key}' | base64 -d)
                ROOT_TOKEN=$(kubectl get secret vault-init-keys -n ${var.vault_namespace} -o jsonpath='{.data.root-token}' | base64 -d)
              fi

              echo "Unsealing Vault..."
              curl -s -X PUT http://vault:8200/v1/sys/unseal \
                -d "{\"key\":\"$UNSEAL_KEY\"}"

              echo "Logging in..."
              vault login $ROOT_TOKEN

              echo "Enabling KV secrets engine..."
              vault secrets enable -path=secret kv-v2 || true

              echo "Storing PostgreSQL credentials..."
              vault kv put secret/finanzwerk/postgres \
                username=${var.postgres_finanzwerk_owner_username} \
                password=${var.postgres_finanzwerk_owner_password}

              echo "Creating policy..."
              vault policy write finanzwerk-data - <<POLICY
              path "secret/data/finanzwerk/*" {
                capabilities = ["read"]
              }
              POLICY

              echo "Done!"
            EOT
          ]


          env {
            name  = "VAULT_ADDR"
            value = "http://${var.vault_endpoint}"
          }
        }
      }
    }
  }
}


resource "kubernetes_service_account_v1" "vault_init" {
  metadata {
    name      = "vault-init"
    namespace = var.vault_namespace
  }
}

resource "kubernetes_role_v1" "vault_init" {
  metadata {
    name      = "vault-init"
    namespace = var.vault_namespace
  }
  rule {
    api_groups = [""]
    resources  = ["secrets"]
    verbs      = ["create", "get", "patch"]
  }
}

resource "kubernetes_role_binding_v1" "vault_init" {
  metadata {
    name      = "vault-init"
    namespace = var.vault_namespace
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = "vault-init"
  }
  subject {
    kind      = "ServiceAccount"
    name      = "vault-init"
    namespace = var.vault_namespace
  }
}

resource "kubernetes_secret_v1" "vault_init_keys" {
  metadata {
    name      = "vault-init-keys"
    namespace = var.vault_namespace
  }
  data = {
    unseal-key = ""
    root-token = ""
  }
}
