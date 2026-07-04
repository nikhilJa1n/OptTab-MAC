#!/bin/bash
set -e

CERT_NAME="AdvancedDockDeveloper"

# Create OpenSSL config file
cat > codesign.cnf <<EOF
[ req ]
default_bits = 2048
prompt = no
distinguished_name = dn
x509_extensions = v3_req

[ dn ]
CN = ${CERT_NAME}

[ v3_req ]
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

echo "=== Generating private key and certificate ==="
openssl req -x509 -config codesign.cnf -days 3650 -out codesign_cert.pem -keyout codesign_key.pem -newkey rsa:2048 -nodes

echo "=== Converting certificate to PKCS#12 format ==="
openssl pkcs12 -export -legacy -out codesign.p12 -inkey codesign_key.pem -in codesign_cert.pem -passout pass:123456

echo "=== Importing certificate into login keychain ==="
security import codesign.p12 -k ~/Library/Keychains/login.keychain-db -P 123456 -T /usr/bin/codesign

# Clean up temp files
rm codesign.cnf codesign_cert.pem codesign_key.pem codesign.p12

echo "=== Certificate successfully created and imported! ==="
security find-identity -p codesigning -v
