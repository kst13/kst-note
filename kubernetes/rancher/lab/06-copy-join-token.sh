#!/usr/bin/env bash
# [Mac] 부록 7.4: mgmt-1 의 server token 을 mgmt-2, mgmt-3 의 /etc/rancher/rke2/server-token 으로 복사
# 설치 문서 4단계(mgmt-1 RKE2 기동) 뒤, 6단계(조인) 전에 실행한다. 토큰은 화면에 출력하지 않는다.
set -euo pipefail
source "$(dirname "$0")/lab.conf.sh"

SRC=/var/lib/rancher/rke2/server/token
vm_sh mgmt-1 sudo test -s "$SRC" || die "mgmt-1 에 $SRC 가 없음. 설치 문서 4단계 먼저"

for n in mgmt-2 mgmt-3; do
  vm_running "$n" || die "$n 이 실행 중이 아님"
  if vm_sh "$n" sudo test -s /etc/rancher/rke2/server-token; then
    echo "$n: 이미 server-token 있음. 바꾸려면 직접 지운 뒤 다시 실행"
    continue
  fi
  vm_sh "$n" sudo install -d -m 700 /etc/rancher/rke2
  vm_sh mgmt-1 sudo cat "$SRC" | vm_sh "$n" sudo sh -c 'umask 077; cat > /etc/rancher/rke2/server-token'
  # 600 root 이고 크기가 0보다 커야 함
  vm_sh "$n" sudo stat -c "$n: %a %U %s bytes %n" /etc/rancher/rke2/server-token
done
