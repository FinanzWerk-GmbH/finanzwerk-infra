# CI/CD Comparison: GitLab CI vs Azure DevOps

FinanzWerk's three pipelines — dbt CI, Terraform with approval, and Python tests — are implemented in both GitLab CI and Azure DevOps. This document records the differences and the decision framework for choosing between them in a German enterprise context.

## Side-by-side: pipeline concepts

| Concern | GitLab CI | Azure DevOps |
|---|---|---|
| Pipeline definition | `.gitlab-ci.yml` | `azure-pipelines.yml` |
| Stage model | `stages:` top-level list, jobs declare their stage | `stages:` → `jobs:` → `steps:` nested hierarchy |
| Approval gates | Protected environments + `when: manual` | `deployment` job type + Environment approval checks |
| Secret storage | CI/CD variables (masked/protected), group variables | Variable groups in Library, secret variables |
| Authentication to cloud | OIDC with `id_tokens:` block, no stored credentials | Service connections (OIDC or key-based), referenced by name |
| Test result publishing | JUnit XML uploaded as artifact, rendered in MR | `PublishTestResults@2` task, rendered in pipeline summary |
| Trigger on PR | `rules: - if: $CI_MERGE_REQUEST_ID` | `pr:` top-level block |
| Manual trigger | `when: manual` on a job | `trigger: none` + `deployment` job type |
| Self-hosted runners | GitLab Runner (Docker, Kubernetes executor) | Azure self-hosted agents |
| Built-in task marketplace | No official marketplace, uses `script:` with apt | Marketplace of 1000+ verified tasks (`UsePythonVersion@0`, `TerraformTaskV4@4`) |
| Reusable components | `include:` for templates, `extends:` for inheritance | Template files, task groups, YAML templates |
| Artefact retention | Configurable per job, default 30 days | Configurable per artifact publish step |

## The same pipeline in both syntaxes

### Approval gate before production deploy

**GitLab CI:**
```yaml
deploy:prod:
  stage: deploy
  environment:
    name: production
  when: manual          # human clicks "play" in the UI
  needs: [plan]
  script: terraform apply tfplan
```

**Azure DevOps:**
```yaml
- stage: Apply
  jobs:
    - deployment: terraform_apply
      environment: production   # environment has "Approvals" check configured in UI
      strategy:
        runOnce:
          deploy:
            steps:
              - script: terraform apply tfplan
```

The end result is identical: a human must approve before the job runs. The mechanism differs: GitLab uses `when: manual` (the runner waits for a button click), Azure DevOps uses environment approval checks (a separate approval workflow fires before the deployment job is assigned to a runner).

### Secret injection

**GitLab CI:**
```yaml
variables:
  DB_PASSWORD: $FINANZWERK_DB_PASSWORD  # set in CI/CD → Variables
script:
  - dbt run
```

**Azure DevOps:**
```yaml
variables:
  - group: finanzwerk-db-credentials   # Library → Variable Groups
steps:
  - script: dbt run
    env:
      DB_PASSWORD: $(db_password)      # $(var_name) syntax
```

Both mask the secret in logs. GitLab uses `$VAR` shell interpolation; Azure uses `$(var)` task variable expansion — the values never appear in the YAML.

## German enterprise context: when to choose which

**Choose Azure DevOps when:**
- The customer is on Azure (common in German banking: ING-DiBa, Commerzbank, many Sparkassen)
- The project is in the Microsoft ecosystem (Azure Active Directory, Teams, SharePoint)
- BaFin or BSI audit requires a full audit trail — Azure DevOps's approval history integrates directly into Azure Monitor
- The customer already has Microsoft 365 E3/E5 (Azure DevOps is included)
- The team uses Jira or Azure Boards for tickets (Azure DevOps Boards integrates natively)

**Choose GitLab CI when:**
- The company wants self-hosted (data sovereignty concern, common in German Mittelstand and public sector)
- The repo is on GitLab (merge requests, review apps, and CI are one product)
- DevSecOps tooling (SAST, DAST, dependency scanning) is a priority — GitLab's security features are first-class
- The project crosses cloud providers and needs a neutral CI system

**Choose GitHub Actions when:**
- The project is open source or the team has a GitHub Enterprise agreement
- The workflow needs the GitHub Actions marketplace (largest ecosystem)
- The company uses GitHub Copilot and wants tight integration

## DORA compliance relevance

Both Azure DevOps and GitLab CI satisfy the change management requirements implied by DORA Article 9 (ICT security policy includes change control) and ISO 27001 A.12.1.2 (change management procedures):

- Every production change is documented in the pipeline run history (who triggered, when, what changed)
- Approval gates provide the four-eyes principle for production deployments
- Artefacts (Terraform plans, dbt manifests) are immutable and traceable to the exact commit

The specific tool doesn't matter for DORA compliance — what matters is that approvals are recorded and auditable. Both tools produce that audit trail.
