#!/usr/bin/env bash
# [Mac] 부록 7.5 (DEV는 8장 3번): 실습 CA 생성, VM과 Mac 키체인에 신뢰 등록
# 사용법: ./05-lab-ca.sh [mgmt|dev|all|VM이름...]   기본값 mgmt
# CA 는 mgmt-1 안에서 한 번만 만든다. ca.key 는 mgmt-1 밖으로 나오지 않는다.
set -euo pipefail
source "$(dirname "$0")/lab.conf.sh"

vm_running mgmt-1 || die "mgmt-1 이 실행 중이 아님"
TARGETS=$(resolve_vms mgmt "$@")

info "mgmt-1: 실습 CA 와 Rancher 인증서 (이미 있으면 그대로 사용)"
vm_sh mgmt-1 bash -s -- "$RANCHER_HOST" < "$LAB_DIR/guest/make-ca.sh"

mkdir -p "$LAB_HOME"
limactl copy mgmt-1:/tmp/lab-ca.pem "$LAB_HOME/cacerts.pem"

for n in $TARGETS; do
  vm_running "$n" || { echo "$n: 실행 중이 아니라 건너뜀"; continue; }
  info "$n: CA 신뢰 등록"
  [ "$n" = mgmt-1 ] || limactl copy "$LAB_HOME/cacerts.pem" "${n}:/tmp/lab-ca.pem"
  vm_sh "$n" sudo sh -c 'install -m 644 /tmp/lab-ca.pem /etc/pki/ca-trust/source/anchors/lab-ca.pem && update-ca-trust'
done

# Mac 로그인 키체인. 이미 있으면 건너뜀. Mac 로그인 비밀번호를 물을 수 있음
KC="$HOME/Library/Keychains/login.keychain-db"
if ! security find-certificate -c "Lab Internal Root CA" "$KC" >/dev/null 2>&1; then
  info "Mac 로그인 키체인에 실습 CA 신뢰 추가"
  security add-trusted-cert -r trustRoot -k "$KC" "$LAB_HOME/cacerts.pem"
fi
info "완료. 설치 문서 8.1 의 인증서 디렉터리는 위에 출력된 경로"
