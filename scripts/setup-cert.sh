#!/bin/bash
#
# setup-cert.sh — create a persistent self-signed code signing certificate
# named "cqlb-dev" in the login keychain, if one doesn't already exist.
#
# Rationale: ad-hoc signatures (`codesign --sign -`) produce a new cdhash
# every rebuild, and macOS TCC tracks Accessibility grants by cdhash plus
# designated requirement. Every rebuild therefore wipes the user's grant.
#
# A stable self-signed cert solves this: the designated requirement is
# derived from the leaf certificate's fingerprint, which stays the same
# across rebuilds. TCC keeps the grant alive.
#
# This script is idempotent — it exits cleanly if the cert is already there.

set -euo pipefail

CERT_NAME="cqlb-dev"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-certificate -c "$CERT_NAME" "$KEYCHAIN" >/dev/null 2>&1; then
  echo "cert '$CERT_NAME' already exists in login keychain"
  exit 0
fi

echo "creating self-signed code signing cert '$CERT_NAME'…"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

cat > "$TMPDIR/cert.cnf" <<EOF
[ req ]
default_bits = 2048
prompt = no
default_md = sha256
distinguished_name = dn
x509_extensions = v3_req

[ dn ]
CN = $CERT_NAME
O = cqlb-dev
C = US

[ v3_req ]
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
basicConstraints = critical, CA:FALSE
subjectKeyIdentifier = hash
EOF

openssl req -x509 -new -nodes -newkey rsa:2048 \
    -keyout "$TMPDIR/key.pem" \
    -out "$TMPDIR/cert.pem" \
    -days 3650 \
    -config "$TMPDIR/cert.cnf" >/dev/null 2>&1

# macOS `security import` doesn't reliably accept empty P12 passwords;
# use a throwaway one. Also force legacy PBE-SHA1-3DES because openssl 3
# defaults to PBES2/AES which macOS' security tool can't decrypt.
P12_PASS="cqlb-dev-import"
openssl pkcs12 -export -legacy -out "$TMPDIR/cert.p12" \
    -inkey "$TMPDIR/key.pem" -in "$TMPDIR/cert.pem" \
    -passout "pass:$P12_PASS" \
    >/dev/null 2>&1 || \
openssl pkcs12 -export -out "$TMPDIR/cert.p12" \
    -inkey "$TMPDIR/key.pem" -in "$TMPDIR/cert.pem" \
    -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES \
    -macalg sha1 \
    -passout "pass:$P12_PASS" \
    >/dev/null 2>&1

# Import into login keychain. `-T /usr/bin/codesign -A` allows codesign
# to use the private key without prompts.
security import "$TMPDIR/cert.p12" \
    -k "$KEYCHAIN" \
    -P "$P12_PASS" \
    -T /usr/bin/codesign \
    -A \
    >/dev/null

# On newer macOS, keys additionally have a "partition list" ACL. Updating
# it requires the keychain password, so this step is best-effort — if it
# prompts or fails, codesign will still often work via the -T entry above.
security set-key-partition-list \
    -S "apple-tool:,apple:,codesign:" \
    -s \
    "$KEYCHAIN" >/dev/null 2>&1 || true

echo "cert '$CERT_NAME' installed in login keychain"
