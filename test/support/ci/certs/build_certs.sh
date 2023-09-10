#!/bin/bash

set -euo pipefail

mkdir -p newcerts
touch index.txt
echo '01' > serial

#build CA certificate
echo "building CA certs..."
openssl genrsa -out ca.key 4096
openssl req -x509 -new -nodes \
  -key ca.key \
  -subj "/C=PT/ST=LX/O=Bumbaklat/CN=httpx-ca" \
  -sha256 -days 358000 \
  -out ca.crt


cat << EOF > ca.cnf
# we use 'ca' as the default section because we're usign the ca command
[ ca ]
default_ca = my_ca

[ my_ca ]
#  a text file containing the next serial number to use in hex. Mandatory.
#  This file must be present and contain a valid serial number.
serial = ./serial

# the text database file to use. Mandatory. This file must be present though
# initially it will be empty.
database = ./index.txt

# specifies the directory where new certificates will be placed. Mandatory.
new_certs_dir = ./newcerts

# the file containing the CA certificate. Mandatory
certificate = ./ca.crt

# the file contaning the CA private key. Mandatory
private_key = ./ca.key

# the message digest algorithm. Remember to not use MD5
default_md = sha256

# for how many days will the signed certificate be valid
default_days = 365

# a section with a set of variables corresponding to DN fields
policy = my_policy

[ my_policy ]
# if the value is "match" then the field value must match the same field in the
# CA certificate. If the value is "supplied" then it must be present.
# Optional means it may be present. Any fields not mentioned are silently
# deleted.
countryName = match
stateOrProvinceName = supplied
organizationName = supplied
commonName = supplied
organizationalUnitName = optional
commonName = supplied

[ ca ]
default_ca = my_ca

[ my_ca ]
#  a text file containing the next serial number to use in hex. Mandatory.
#  This file must be present and contain a valid serial number.
serial = ./serial

# the text database file to use. Mandatory. This file must be present though
# initially it will be empty.
database = ./index.txt

# specifies the directory where new certificates will be placed. Mandatory.
new_certs_dir = ./newcerts

# the file containing the CA certificate. Mandatory
certificate = ./ca.crt

# the file contaning the CA private key. Mandatory
private_key = ./ca.key

# the message digest algorithm. Remember to not use MD5
default_md = sha256

# for how many days will the signed certificate be valid
default_days = 365

# a section with a set of variables corresponding to DN fields
policy = my_policy

[ my_policy ]
# if the value is "match" then the field value must match the same field in the
# CA certificate. If the value is "supplied" then it must be present.
# Optional means it may be present. Any fields not mentioned are silently
# deleted.
countryName = match
stateOrProvinceName = supplied
organizationName = supplied
commonName = supplied
organizationalUnitName = optional
commonName = supplied
EOF
echo "CA certs built!!!"

# build server certificate
echo "building server certs..."
# setup config with alternative names
cat << EOF > server.cnf
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req

[req_distinguished_name]
countryName = Country Name (2 letter code)
countryName_default = PT
stateOrProvinceName = State or Province Name (full name)
stateOrProvinceName_default = LX
localityName = Locality Name (eg, city)
localityName_default = Lisbon
0.organizationName = Organizational Unit Name (eg, section)
organizationalUnitName  = Organizational Unit Name (eg, section)
organizationalUnitName_default  = Domain Control Validated
commonName = Internet Widgits Ltd
commonName_max  = 64

[ v3_req ]
# Extensions to add to a certificate request
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
subjectAltName = @alt_names

[alt_names]
DNS.1 = nghttp2
DNS.2 = another
DNS.3 = another2
EOF

# build server certs
openssl genrsa -out server.key 2048

openssl req -new -sha256 \
  -key server.key \
  -subj "/C=PT/ST=LX/O=Bumbaklat/OU=nghttp2/CN=nghttp2" \
  -config server.cnf \
  -out server.csr

openssl x509 -req -in server.csr \
  -CA ca.crt \
  -CAkey ca.key \
  -CAcreateserial -out server.crt \
  -days 358000


cat << EOF > server.extensions.cnf
basicConstraints=CA:FALSE
subjectAltName=@my_subject_alt_names
subjectKeyIdentifier = hash

[ my_subject_alt_names ]
DNS.1 = nghttp2
DNS.2 = another
DNS.3 = another2
EOF

openssl ca -config ca.cnf -out server.crt -extfile server.extensions.cnf -in server.csr -batch
echo "server certs built!!!"

# build localhost server certs
cat << EOF > localhost-server.cnf
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req

[req_distinguished_name]
countryName = Country Name (2 letter code)
countryName_default = PT
stateOrProvinceName = State or Province Name (full name)
stateOrProvinceName_default = LX
localityName = Locality Name (eg, city)
localityName_default = Lisbon
0.organizationName = Organizational Unit Name (eg, section)
organizationalUnitName  = Organizational Unit Name (eg, section)
organizationalUnitName_default  = Domain Control Validated
commonName = Internet Widgits Ltd
commonName_max  = 64

[ v3_req ]
# Extensions to add to a certificate request
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
subjectAltName = @alt_names

[alt_names]
DNS.1 = localhost
IP.2 = 127.0.0.1
IP.3 = 0000:0000:0000:0000:0000:0000:0000:0001
EOF

echo "building localhost server certs..."
openssl genrsa -out localhost-server.key 2048
openssl req -new -sha256 \
  -key localhost-server.key \
  -subj "/C=PT/ST=LX/O=Bumbaklat/CN=localhost-server" \
  -config localhost-server.cnf \
  -out localhost-server.csr

openssl x509 -req -in localhost-server.csr \
  -CA ca.crt \
  -CAkey ca.key \
  -CAcreateserial -out localhost-server.crt \
  -days 358000

cat << EOF > localhost-server.extensions.cnf
basicConstraints=CA:FALSE
subjectAltName=@my_subject_alt_names
subjectKeyIdentifier = hash

[ my_subject_alt_names ]
DNS.1 = localhost
IP.2 = 127.0.0.1
IP.3 = 0000:0000:0000:0000:0000:0000:0000:0001
EOF

openssl ca -config ca.cnf -out localhost-server.crt -extfile localhost-server.extensions.cnf -in localhost-server.csr -batch
echo "localhost server certs built!!!"

# build DOH certificate
echo "building DOH certs..."
openssl genrsa -out doh.key 2048
openssl req -new -sha256 \
  -key doh.key \
  -subj "/C=PT/ST=LX/O=Bumbaklat/CN=doh" \
  -out doh.csr

openssl x509 -req -in doh.csr \
  -CA ca.crt \
  -CAkey ca.key \
  -CAcreateserial -out doh.crt \
  -days 358000 -sha256
echo "DOH certs built!!!"

# ca-bundle.crt
echo "building ca-bundle..."
cat doh.crt localhost-server.crt server.crt ca.crt > ca-bundle.crt
echo "ca-bundle built!!!"

# verification steps
openssl verify -CAfile ca.crt server.crt
echo "server verified!"
openssl verify -CAfile ca.crt localhost-server.crt
echo "server verified!"
openssl verify -CAfile ca.crt doh.crt
echo "doh verified!"
