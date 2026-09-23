#!/usr/bin/env bash
# Mint a local development CA and a certificate for localhost, the way mkcert does.
#
# Why: a browser will not use HTTP/3 (so: no WebTransport) for an origin whose certificate it does not
# trust. A self-signed leaf cannot fix that - the browser refuses a non-CA certificate as an anchor, and
# Chromium verifies QUIC certificates separately from the HTTP ones, so the page can load while every
# QUIC handshake dies with "46: certificate unknown". A locally trusted CA fixes both.
#
# Usage:
#   scripts/dev_cert.sh                 mint or reuse a CA, mint a leaf, stage the demo's cert files
#   scripts/dev_cert.sh --out DIR       where the CA and leaf live            (default .dev-certs)
#   scripts/dev_cert.sh --stage DIR     directory the demos load certs from   (default examples/certs)
#   scripts/dev_cert.sh --trust         install the CA into this machine's stores (prints every command)
#
# The CA is reused across runs, so it is trusted once. Nothing is installed into a trust store unless
# --trust is passed, and each command is printed before it runs.
set -euo pipefail

out=.dev-certs
stage=examples/certs
trust=no

while [ $# -gt 0 ]; do
    case "$1" in
        --out) out=$2; shift 2 ;;
        --stage) stage=$2; shift 2 ;;
        --trust) trust=yes; shift ;;
        -h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

mkdir -p "$out"

# The CA is minted once and reused: a browser that trusts it keeps trusting every leaf it signs.
if [ ! -f "$out/ca.pem" ] || [ ! -f "$out/ca.key" ]; then
    echo "minting a development CA in $out"
    openssl ecparam -name prime256v1 -genkey -noout -out "$out/ca.key"
    openssl req -x509 -new -key "$out/ca.key" -sha256 -days 3650 \
        -subj "/O=zix development/CN=zix development CA" \
        -addext "basicConstraints=critical,CA:TRUE" \
        -addext "keyUsage=critical,keyCertSign,cRLSign" \
        -out "$out/ca.pem"
else
    echo "reusing the CA in $out"
fi

echo "minting a leaf for localhost"
openssl ecparam -name prime256v1 -genkey -noout -out "$out/leaf.key"
openssl req -new -key "$out/leaf.key" -subj "/CN=localhost" -out "$out/leaf.csr"
printf 'basicConstraints=CA:FALSE\nkeyUsage=digitalSignature\nextendedKeyUsage=serverAuth\nsubjectAltName=DNS:localhost,IP:127.0.0.1\n' > "$out/leaf.ext"
openssl x509 -req -in "$out/leaf.csr" -CA "$out/ca.pem" -CAkey "$out/ca.key" -CAcreateserial \
    -days 825 -sha256 -extfile "$out/leaf.ext" -out "$out/leaf.pem"
rm -f "$out/leaf.csr" "$out/leaf.ext" "$out/ca.srl"

# The demos load these two paths relative to their working directory.
mkdir -p "$stage"
cp "$out/leaf.pem" "$stage/ecdsa_p256_cert.pem"
cp "$out/leaf.key" "$stage/ecdsa_p256_key.pem"
echo "staged $stage/ecdsa_p256_cert.pem (leaf signed by the CA in $out)"

openssl x509 -in "$out/ca.pem" -outform der -out "$out/ca.crt"

cat <<EOF

Trust the CA once, then restart the browser. Any one of these is enough for the browser you use:

  Windows, current user, no administrator needed (this is the mkcert behaviour):
    certutil -user -addstore -f ROOT $(cygpath -w "$out/ca.crt" 2>/dev/null || echo "$out/ca.crt")
    remove it later with: certutil -user -delstore ROOT "zix development CA"

  Linux, system store plus the browser's own:
    sudo cp $out/ca.pem /usr/local/share/ca-certificates/zix-dev-ca.crt && sudo update-ca-certificates
    certutil -d sql:\$HOME/.pki/nssdb -A -t "C,," -n "zix development CA" -i $out/ca.pem

  macOS:
    sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain $out/ca.crt

Run the demo from a directory where $stage/*.pem is the demo's own cert path, then open
https://127.0.0.1:9444/ and press "open session".
EOF

if [ "$trust" = yes ]; then
    echo
    echo "--trust was passed; running the commands for this platform"
    case "$(uname -s)" in
        Linux)
            echo "+ sudo cp $out/ca.pem /usr/local/share/ca-certificates/zix-dev-ca.crt"
            echo "+ sudo update-ca-certificates"
            sudo cp "$out/ca.pem" /usr/local/share/ca-certificates/zix-dev-ca.crt
            sudo update-ca-certificates
            if command -v certutil >/dev/null 2>&1; then
                echo "+ certutil -d sql:\$HOME/.pki/nssdb -A -t C,, -n 'zix development CA' -i $out/ca.pem"
                certutil -d sql:"$HOME/.pki/nssdb" -A -t "C,," -n "zix development CA" -i "$out/ca.pem" || true
            else
                echo "note: install libnss3-tools for the browser's own store (certutil not found)"
            fi
            ;;
        Darwin)
            echo "+ sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain $out/ca.crt"
            sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain "$out/ca.crt"
            ;;
        *) echo "on Windows run the certutil line above" ;;
    esac
fi
