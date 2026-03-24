resource "helm_release" "vault" {
  name       = "vault"
  repository = "https://helm.releases.hashicorp.com"
  chart      = "hashicorp/vault"
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
    }
  ]
  set_list = [
    {
      name  = "server.ingress.hosts[0].host"
      value = var.vault_host
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
              # Wait for Vault to be ready
              until vault status 2>/dev/null; do
                echo "Waiting for Vault..."
                sleep 3
              done

              # Init Vault (only if not already initialized)
              if ! vault status | grep -q "Initialized.*true"; then
                vault operator init -key-shares=1 -key-threshold=1 -format=json > /tmp/init.json
                UNSEAL_KEY=$(cat /tmp/init.json | jq -r '.unseal_keys_b64[0]')
                ROOT_TOKEN=$(cat /tmp/init.json | jq -r '.root_token')

                vault operator unseal $UNSEAL_KEY

                # Save keys to a Kubernetes secret for later use
                kubectl patch secret vault-init-keys \
                -n ${var.vault_namespace} \
                -p "{\"data\":{\"unseal-key\":\"$(echo -n $UNSEAL_KEY | base64)\",\"root-token\":\"$(echo -n $ROOT_TOKEN | base64)\"}}"
              else
                ROOT_TOKEN=$(kubectl get secret vault-init-keys -n ${var.vault_namespace} -o jsonpath='{.data.root-token}' | base64 -d)
                UNSEAL_KEY=$(kubectl get secret vault-init-keys -n ${var.vault_namespace} -o jsonpath='{.data.unseal-key}' | base64 -d)
                vault operator unseal $UNSEAL_KEY
              fi

              vault login $ROOT_TOKEN

              # Enable KV secrets engine
              vault secrets enable -path=secret kv-v2 || true

              # Store PostgreSQL credentials
              vault kv put secret/finanzwerk/postgres \
                username=${var.postgres_finanzwerk_owner_username} \
                password=${var.postgres_finanzwerk_owner_password}

              # Create policy
              vault policy write finanzwerk-data - <<POLICY
              path "secret/data/finanzwerk/*" {
                capabilities = ["read"]
              }
              POLICY
            EOT
          ]

          env {
            name  = "VAULT_ADDR"
            value = "http://vault:8200"
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
    verbs      = ["create", "get"]
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
