#!/usr/bin/env bash
# =============================================================================
# One-time setup of mutual-TLS certs for AWS Client VPN.
#
# Generates:
#   pki/server.crt + server.key  -> upload to ACM, ARN -> vpn_server_cert_arn
#   pki/ca.crt                   -> upload to ACM, ARN -> vpn_client_root_cert_arn
#   pki/client.<name>.crt|.key   -> hand to each peer, embed in their .ovpn
#
# Requires: easy-rsa (`brew install easy-rsa` / `apt install easy-rsa`).
# =============================================================================
set -euo pipefail

PEER_NAME="${1:-developer-1}"
PKI_DIR="$(cd "$(dirname "$0")/.." && pwd)/.pki"
mkdir -p "$PKI_DIR"
cd "$PKI_DIR"

if ! command -v easyrsa >/dev/null 2>&1; then
  echo "ERROR: easy-rsa not installed. brew/apt install easy-rsa." >&2
  exit 1
fi

if [[ ! -d pki ]]; then
  easyrsa init-pki
  easyrsa --batch build-ca nopass
fi

if [[ ! -f pki/issued/server.crt ]]; then
  easyrsa --batch build-server-full server nopass
fi

if [[ ! -f "pki/issued/${PEER_NAME}.crt" ]]; then
  easyrsa --batch build-client-full "$PEER_NAME" nopass
fi

echo
echo "PKI artifacts ready in $PKI_DIR/pki"
echo
echo "Next steps:"
echo "  1) Upload server cert to ACM:"
echo "     aws acm import-certificate \\"
echo "       --certificate fileb://pki/issued/server.crt \\"
echo "       --private-key fileb://pki/private/server.key \\"
echo "       --certificate-chain fileb://pki/ca.crt"
echo
echo "  2) Upload CA root to ACM (used for client auth):"
echo "     aws acm import-certificate \\"
echo "       --certificate fileb://pki/ca.crt \\"
echo "       --private-key fileb://pki/private/ca.key"
echo
echo "  3) After 'terraform apply', download the .ovpn template:"
echo "     aws ec2 export-client-vpn-client-configuration \\"
echo "       --client-vpn-endpoint-id \$(terraform output -raw client_vpn_endpoint_id) \\"
echo "       --output text > prime.ovpn"
echo
echo "  4) Append peer cert+key to prime.ovpn:"
echo "     cat >> prime.ovpn <<EOF"
echo "     <cert>"
echo "     \$(cat pki/issued/${PEER_NAME}.crt)"
echo "     </cert>"
echo "     <key>"
echo "     \$(cat pki/private/${PEER_NAME}.key)"
echo "     </key>"
echo "     EOF"
echo
echo "  5) Distribute prime.ovpn securely to ${PEER_NAME}."
