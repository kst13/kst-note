#!/usr/bin/env bash
# [mgmt-1, 일반 계정] 05-lab-ca.sh 가 표준입력으로 넘겨 실행한다. 부록 7.5의 실습 CA와 Rancher 인증서 생성.
# 인자: <Rancher FQDN>. 이미 있으면 다시 만들지 않는다.
set -euo pipefail
RANCHER_HOST=$1
CA_DIR="$HOME/lab-ca"

install -d -m 700 "$CA_DIR"
cd "$CA_DIR"
umask 077

if [ ! -s tls.crt ]; then
  # 1) 실습용 루트 CA (10년)
  openssl req -x509 -newkey rsa:4096 -sha256 -days 3650 -nodes \
    -keyout ca.key -out cacerts.pem -subj "/CN=Lab Internal Root CA" \
    -addext "basicConstraints=critical,CA:TRUE" -addext "keyUsage=critical,keyCertSign,cRLSign" 2>/dev/null
  # 2) Rancher 서버용 개인키와 인증서 요청서
  openssl req -newkey rsa:2048 -nodes -keyout tls.key -out tls.csr -subj "/CN=${RANCHER_HOST}" 2>/dev/null
  # 3) CA로 서버 인증서 발급. SAN에 Rancher 도메인을 넣음
  printf 'subjectAltName=DNS:%s\nextendedKeyUsage=serverAuth\nkeyUsage=critical,digitalSignature,keyEncipherment\n' "$RANCHER_HOST" > san.ext
  openssl x509 -req -in tls.csr -CA cacerts.pem -CAkey ca.key -CAcreateserial \
    -out tls.crt -days 825 -sha256 -extfile san.ext 2>/dev/null
fi

openssl x509 -in tls.crt -noout -subject -issuer -ext subjectAltName
# 다른 VM과 Mac에 나눠 줄 CA 사본. CA 인증서는 공개해도 되는 파일이라 644
install -m 644 cacerts.pem /tmp/lab-ca.pem
echo "설치 문서 8.1 인증서 디렉터리: $CA_DIR"
