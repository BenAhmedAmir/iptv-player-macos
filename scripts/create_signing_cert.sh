#!/bin/bash
#
# Creates a self-signed code-signing certificate in the login keychain so the app
# gets a *stable* code signature across rebuilds.
#
# Why this exists: an ad-hoc signature (`codesign --sign -`) gives the app a
# designated requirement of `cdhash H"<hash of this exact binary>"`. Keychain
# item ACLs are recorded against that requirement, so every rebuild invalidates
# them and macOS prompts for the login keychain password again. Signing with a
# real certificate makes the requirement identifier + certificate based, which
# does not change when the binary does — so clicking "Always Allow" once sticks.
#
# Run once. It is interactive: macOS will ask you to authorise the trust-setting
# change for the new certificate.

set -euo pipefail

CERT_NAME="IPTV Player Dev"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning | grep -qF "$CERT_NAME"; then
    echo "✅ Signing identity \"$CERT_NAME\" already exists. Nothing to do."
    echo "   Build with: scripts/build_app.sh release"
    exit 0
fi

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

echo "🔑 Generating a self-signed code-signing certificate (\"$CERT_NAME\")..."

# Code signing requires these extensions; a bare self-signed cert will not do.
cat << EOF > "$WORK_DIR/openssl.cnf"
[ req ]
distinguished_name = dn
x509_extensions    = ext
prompt             = no

[ dn ]
CN = $CERT_NAME

[ ext ]
basicConstraints       = critical,CA:false
keyUsage               = critical,digitalSignature
extendedKeyUsage       = critical,codeSigning
subjectKeyIdentifier   = hash
EOF

openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
    -config "$WORK_DIR/openssl.cnf" \
    -keyout "$WORK_DIR/key.pem" \
    -out "$WORK_DIR/cert.pem" 2>/dev/null

# Bundle key + cert so the private key lands in the keychain alongside the cert.
#
# Two PKCS#12 details are load-bearing for Apple's importer, which otherwise
# fails with "MAC verification failed during PKCS12 import (wrong password?)":
#   1. OpenSSL 3 defaults to AES-256-CBC/PBKDF2 with a SHA-256 MAC. Apple's
#      parser rejects that, so pin the legacy SHA1/3DES algorithms.
#   2. An empty password is MAC-encoded differently by OpenSSL and Apple, so use
#      a throwaway non-empty one. It never leaves this script's temp directory.
P12_PASS="transient-$$"

export_p12() {
    "$1" pkcs12 -export \
        -inkey "$WORK_DIR/key.pem" \
        -in "$WORK_DIR/cert.pem" \
        -name "$CERT_NAME" \
        -certpbe PBE-SHA1-3DES \
        -keypbe PBE-SHA1-3DES \
        -macalg sha1 \
        -passout pass:"$P12_PASS" \
        -out "$WORK_DIR/identity.p12" 2>/dev/null
}

# LibreSSL at /usr/bin/openssl already defaults to Apple-compatible algorithms,
# so it is a dependable fallback if the OpenSSL on PATH rejects these flags.
if ! export_p12 openssl && ! export_p12 /usr/bin/openssl; then
    echo "❌ Failed to build the PKCS#12 bundle." >&2
    exit 1
fi

echo "📥 Importing into the login keychain..."
# -T grants codesign non-interactive access to the private key, so builds do not
# prompt. -A is deliberately avoided: it would allow *every* binary to use it.
security import "$WORK_DIR/identity.p12" \
    -k "$KEYCHAIN" \
    -P "$P12_PASS" \
    -T /usr/bin/codesign \
    -T /usr/bin/security

# Without this, codesign refuses the identity as not valid for code signing.
echo "🔐 Marking the certificate as trusted for code signing..."
echo "   (macOS will ask you to authorise this change.)"
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$WORK_DIR/cert.pem"

# Best-effort: the partition list is the newer gate on private-key access, and
# setting it suppresses the "codesign wants to use a key" dialog. It needs the
# login keychain password, which this script deliberately does not ask for, so
# treat failure as fine — the -T flags above already grant codesign access, and
# at worst macOS asks once and "Always Allow" settles it.
security set-key-partition-list \
    -S apple-tool:,apple:,codesign: -s "$KEYCHAIN" >/dev/null 2>&1 || true

if security find-identity -v -p codesigning | grep -qF "$CERT_NAME"; then
    echo
    echo "✅ Done. \"$CERT_NAME\" is now a valid code-signing identity."
    echo
    echo "Next steps:"
    echo "  1. scripts/build_app.sh release"
    echo "  2. Launch the app and open Movies — click \"Always Allow\" on the"
    echo "     keychain prompt once. It will not come back on later rebuilds."
else
    echo "❌ The identity was imported but is not reported as valid." >&2
    echo "   Open Keychain Access, find \"$CERT_NAME\", and set" >&2
    echo "   Trust → Code Signing to \"Always Trust\"." >&2
    exit 1
fi
