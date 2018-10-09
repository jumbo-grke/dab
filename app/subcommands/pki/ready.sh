#!/bin/sh
# Description: Ensure the Public Key Infrastructre is ready for use
# vim: ft=sh ts=4 sw=4 sts=4 noet
set -euf

# shellcheck disable=SC1091
. ./lib.sh

export DAB_PKI_CA_TTL="${DAB_PKI_CA_TTL:-8760h}"

# The 'pki' config namespace will contain machine specific secrets so it should
# be ignored if the config is shared via a tool like git.
config_add .gitignore /pki

# Hashicorp Vault is the pki backend for generation, storage, and renewal.
dab services start vault

# Await the docker health check to indicate the vault api is ready
await_service_healthy vault

if ! vault_initialized; then
	inform 'Initializing Vault...'
	dab config set pki/vault/init "$(vault_init)"
fi

if vault_sealed; then
	inform 'Unsealing Vault'
	quietly vault unseal "$(vault_key)"
fi

silently vault login "$(vault_token)"

if ! vault_pki_enabled; then
	inform 'Enabling Vault PKI'
	vault secrets enable -path=pki_dab pki
	vault write pki_dab/config/urls issuing_certificates="http://vault:8200/v1/pki_dab"
	vault secrets tune -max-lease-ttl="$DAB_PKI_CA_TTL" pki_dab
	ca_cert="$(carelessly vault write -format=json -field=certificate pki_dab/root/generate/internal common_name=dab ttl="$DAB_PKI_CA_TTL")"
	dab config set pki/ca/certificate "$(echo "$ca_cert" | jq -r)"
fi