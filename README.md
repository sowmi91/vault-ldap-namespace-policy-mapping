Vault + OpenLDAP: Example Deployment
This repository contains scripts and instructions to configure HashiCorp Vault (Enterprise or OSS with namespaces support) to authenticate users via OpenLDAP, map LDAP groups to Vault identity groups, and apply namespace-specific policies.

WARNING:
Do not commit real credentials. Use environment variables or secret stores for tokens/passwords.

📂 Repository Contents
File	Description
deploy_vault_ldap.sh	Shell script to run OpenLDAP in Docker, import LDIF, configure Vault LDAP auth, create groups, aliases, namespace, and internal group mapping.
deploy_vault_ldap.py	Python (hvac) equivalent to perform the same Vault operations programmatically.
example.ldif	Example LDIF defining ou=groups, ou=users, group cn=dev, and user cn=laura. (You should replace with your actual LDIF.)

🛠 Prerequisites
Docker installed (for local OpenLDAP)

Vault server running and unsealed (CLI or API reachable)

vault CLI installed and authenticated for admin operations

ldap-utils (for ldapadd) installed locally — or run LDAP commands inside the container

Python 3 and hvac (if using Python script)

pip install hvac
Required environment variables:


export VAULT_ADDR="http://127.0.0.1:8200"
export VAULT_TOKEN="s.xxxxx"        # Vault admin token
export LDAP_ADMIN_PASS="admin"      # Optional, default for osixia image
📜 Example LDAP Structure
example.ldif

ldif

dn: ou=groups,dc=example,dc=org
objectClass: organizationalunit
ou: groups

dn: ou=users,dc=example,dc=org
objectClass: organizationalunit
ou: users

dn: cn=dev,ou=groups,dc=example,dc=org
objectClass: groupofnames
cn: dev
member: cn=laura,ou=users,dc=example,dc=org

dn: cn=laura,ou=users,dc=example,dc=org
objectClass: person
cn: laura
sn: laura
userPassword: laura
🚀 Quick Start — Shell Script
Place your LDIF at ./example.ldif.

Export required environment variables:

export VAULT_ADDR="http://127.0.0.1:8200"
export VAULT_TOKEN="s.xxxxx"
export LDAP_ADMIN_PASS="admin"
Run:


./deploy_vault_ldap.sh ./example.ldif
Login via LDAP:


vault login -method=ldap username=laura
export VAULT_NAMESPACE=test
🚀 Quick Start — Python Script

export VAULT_ADDR="http://127.0.0.1:8200"
export VAULT_TOKEN="s.xxxxx"
python deploy_vault_ldap.py
📋 What the Scripts Do
Start a local OpenLDAP container (osixia/openldap:1.2.1)

Import the LDIF to create users and groups

Enable and configure Vault LDAP auth (root namespace)

Create:

Admin policy in root namespace

Training-admin policy in test namespace

Map LDAP group dev → Vault external identity group → group alias

Create namespace test and internal group Training Admin mapped to the external group

Allow LDAP-authenticated users to work in the namespace with assigned policies

🔒 Security & Cleanup
Store VAULT_TOKEN and LDAP bind password securely

Remove demo LDAP container after testing:


docker stop my-openldap-container && docker rm my-openldap-container
Revoke test tokens and delete test policies/groups after use

🛠 Troubleshooting
LDAP connection issues:
Ensure port 389 is exposed and container is running.


docker ps | grep ldap
Vault command errors:
Ensure Vault is unsealed and VAULT_TOKEN has admin privileges.

Inspect Vault auth methods:


vault auth list
List namespaces:

vault namespace list
📈 Next Steps / Improvements
Replace static passwords with hashed or ephemeral credentials

Add automated tests for the deployment

Use least-privilege policies instead of example admin/training-admin

Optional: GitHub Actions workflow for automated deployment tests
