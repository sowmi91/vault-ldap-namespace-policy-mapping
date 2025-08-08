#!/usr/bin/env bash
set -euo pipefail

# Usage: ./deploy_vault_ldap.sh /path/to/your-ldif-file.ldif
LDIF_FILE="${1:-your-ldif-file.ldif}"

# Required env vars:
#   VAULT_ADDR (e.g. http://127.0.0.1:8200)
#   VAULT_TOKEN (Vault root/admin token)
#   LDAP_ADMIN_PASS (admin password for OpenLDAP; default uses osixia default "admin")
: "${VAULT_ADDR:?Please set VAULT_ADDR (e.g. http://127.0.0.1:8200)}"
: "${VAULT_TOKEN:?Please set VAULT_TOKEN (Vault admin token)}"
LDAP_ADMIN_PASS="${LDAP_ADMIN_PASS:-admin}"

export VAULT_ADDR VAULT_TOKEN

echo "1) Start OpenLDAP docker container..."
docker run --rm -d \
  --name my-openldap-container \
  --hostname ldap.my-company.com \
  -p 389:389 \
  osixia/openldap:1.2.1

sleep 4
echo "docker container status:"
docker ps | grep my-openldap-container || ( echo "OpenLDAP not running" && exit 1 )

echo "2) Import LDIF into LDAP..."
if [[ ! -f "$LDIF_FILE" ]]; then
  echo "LDIF file '$LDIF_FILE' not found. Exiting."
  exit 1
fi
# Note: osixia default admin DN: cn=admin,dc=example,dc=org passwd: admin
ldapadd -x -W -D "cn=admin,dc=example,dc=org" -f "$LDIF_FILE" <<EOF
${LDAP_ADMIN_PASS}
EOF

echo "3) Enable LDAP auth method in Vault (root namespace)..."
vault auth enable ldap || echo "ldap auth may already be enabled"

echo "4) Configure Vault LDAP connection..."
vault write auth/ldap/config \
  url="ldap://localhost" \
  userdn="ou=users,dc=example,dc=org" \
  groupdn="ou=groups,dc=example,dc=org" \
  groupfilter="(|(memberUid={{.Username}})(member={{.UserDN}})(uniqueMember={{.UserDN}}))" \
  groupattr="cn" \
  starttls=false \
  binddn="cn=admin,dc=example,dc=org" \
  bindpass="${LDAP_ADMIN_PASS}"

echo "5) Create an example Vault policy (admin) in root namespace..."
cat > /tmp/admin.hcl <<'EOF'
# admin policy - adjust as required
path "*" { capabilities = ["create","read","update","delete","list","sudo"] }
EOF

vault policy write admin /tmp/admin.hcl

echo "6) Create external identity group 'dev' and capture ID..."
GROUP_JSON=$(vault write -format=json identity/group name=dev type=external policies=admin)
GROUP_ID=$(echo "$GROUP_JSON" | python3 -c "import sys, json as j; print(j.load(sys.stdin)['data']['id'])")
echo "Created external group id: $GROUP_ID"

echo "7) Get LDAP auth mount accessor..."
AUTH_LIST_JSON=$(vault auth list -format=json)
LDAP_ACCESSOR=$(echo "$AUTH_LIST_JSON" | python3 -c "import sys,json; j=json.load(sys.stdin); print([v['accessor'] for k,v in j['data'].items() if k.strip('/')=='ldap'][0])")
echo "LDAP accessor: $LDAP_ACCESSOR"

echo "8) Create group alias (match LDAP group name 'dev')..."
vault write identity/group-alias name=dev mount_accessor="$LDAP_ACCESSOR" canonical_id="$GROUP_ID"

echo "9) Create namespace 'test'..."
vault namespace create test || echo "namespace may already exist"

echo "10) Add training-admin policy in 'test' namespace (example)..."
cat > /tmp/training-admin.hcl <<'EOF'
# training-admin policy example
path "kv/*" {
  capabilities = ["create","read","update","delete","list"]
}
EOF
vault policy write -namespace=test training-admin /tmp/training-admin.hcl

echo "11) Create internal group inside 'test' namespace and map to external dev group..."
vault write -namespace=test identity/group \
  name="Training Admin" \
  policies="training-admin" \
  member_group_ids="$GROUP_ID"

echo "12) Done. You can now login via LDAP (root namespace):"
echo "Example: vault login -method=ldap username=laura"
echo "After login, set VAULT_NAMESPACE=test to act in the test namespace."

# cleanup temporary files
rm -f /tmp/admin.hcl /tmp/training-admin.hcl
