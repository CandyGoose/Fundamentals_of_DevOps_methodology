#!/bin/sh

set -eu

: "${VAULT_ADDR:=http://127.0.0.1:8200}"
: "${VAULT_TOKEN:=root}"
: "${GITLAB_ISSUER:=https://gitlab.com}"
: "${GITLAB_PROJECT_PATH:=group/project}"
: "${VAULT_AUDIENCE:=https://vault.demo.local}"

export VAULT_ADDR
export VAULT_TOKEN

vault secrets enable -path=secret kv-v2 2>/dev/null || true
vault kv put secret/lab4/deploy deploy_token="prod-demo-token"

vault auth enable jwt 2>/dev/null || true
vault write auth/jwt/config \
  oidc_discovery_url="$GITLAB_ISSUER" \
  bound_issuer="$GITLAB_ISSUER"

vault policy write lab4-ci /workspace/vault/policies/lab4-ci.hcl

vault write auth/jwt/role/lab4-ci \
  role_type="jwt" \
  user_claim="sub" \
  bound_audiences="$VAULT_AUDIENCE" \
  bound_claims="{\"project_path\":\"$GITLAB_PROJECT_PATH\",\"ref\":\"main\",\"ref_type\":\"branch\"}" \
  policies="lab4-ci" \
  ttl="5m"
