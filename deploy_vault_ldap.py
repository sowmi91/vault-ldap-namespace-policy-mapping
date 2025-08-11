#!/usr/bin/env python3
"""
deploy_vault_ldap.py
Python version of the Vault+LDAP setup using hvac.
Set env vars: VAULT_ADDR, VAULT_TOKEN. Replace LDAP bindpass as needed.
"""
import os
import sys
import hvac
import json

VAULT_ADDR = os.getenv('VAULT_ADDR')
VAULT_TOKEN = os.getenv('VAULT_TOKEN')
LDAP_BINDPASS = os.getenv('LDAP_ADMIN_PASS', 'admin')

if not VAULT_ADDR or not VAULT_TOKEN:
    print("Please set VAULT_ADDR and VAULT_TOKEN env vars.")
    sys.exit(1)

client = hvac.Client(url=VAULT_ADDR, token=VAULT_TOKEN)
assert client.is_authenticated(), "Vault auth failed with provided token"

# 1) Enable ldap auth (idempotent)
try:
    client.sys.enable_auth_method('ldap')
except Exception as e:
    print("ldap enable may already exist:", e)

# 2) Configure LDAP
client.write('auth/ldap/config', **{
    'url': 'ldap://localhost',
    'userdn': 'ou=users,dc=example,dc=org',
    'groupdn': 'ou=groups,dc=example,dc=org',
    'groupfilter': '(|(memberUid={{.Username}})(member={{.UserDN}})(uniqueMember={{.UserDN}}))',
    'groupattr': 'cn',
    'starttls': 'false',
    'binddn': 'cn=admin,dc=example,dc=org',
    'bindpass': LDAP_BINDPASS
})
print("Configured LDAP auth")

# 3) Create an 'admin' policy in root
admin_policy = """
path "*" { capabilities = ["create","read","update","delete","list","sudo"] }
"""
client.sys.create_or_update_policy(name='admin', policy=admin_policy)
print("admin policy written")

# 4) Create external group 'dev'
create_group = client.write('identity/group', name='dev', type='external', policies='admin')
group_id = create_group['data']['id']
print("Created external group id:", group_id)

# 5) Get ldap auth accessor
auths = client.sys.list_auth_methods()
ldap_accessor = None
for path, meta in auths['data'].items():
    if path.strip('/') == 'ldap':
        ldap_accessor = meta['accessor']
        break
if not ldap_accessor:
    raise RuntimeError("LDAP accessor not found")
print("LDAP accessor:", ldap_accessor)

# 6) Create group alias
client.write('identity/group-alias', name='dev', mount_accessor=ldap_accessor, canonical_id=group_id)
print("Created group alias for 'dev'")

# 7) Create namespace 'test'
try:
    client.write('sys/namespaces/test')
    print("Created namespace 'test'")
except Exception as e:
    print("Namespace may already exist or creation failed:", e)

# 8) Write a sample policy into test namespace
training_admin_policy = """
path "kv/*" {
  capabilities = ["create","read","update","delete","list"]
}
"""
# header for namespace
ns_headers = {'X-Vault-Namespace': 'test'}
client.adapter.headers.update(ns_headers)
client.sys.create_or_update_policy(name='training-admin', policy=training_admin_policy)
print("Wrote training-admin policy in namespace 'test'")

# 9) Create internal group in test namespace mapping to external group
client.write('identity/group', name='Training Admin', policies='training-admin', member_group_ids=group_id)
print("Created internal group 'Training Admin' in test namespace linking to external group_id")

# Done
print("Setup complete. Login via: vault login -method=ldap username=laura")
