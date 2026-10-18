#!/usr/bin/env bash
# [Mac] 부록 4장: VM 고정 IP, /app 디스크 포맷과 마운트
# 사용법: ./03-configure-vms.sh [base|dev|all|VM이름...]   기본값 base
# VM 안에서는 guest/base.sh 가 실행된다. 이미 된 단계는 건너뛴다.
set -euo pipefail
source "$(dirname "$0")/lab.conf.sh"

VMS=$(resolve_vms base "$@")

for n in $VMS; do
  vm_running "$n" || die "$n 이 실행 중이 아님. ./02-create-vms.sh $n 먼저"
  info "$n: 기본 설정"
  vm_sh "$n" sudo bash -s -- "$(vm_field "$n" 2)" "$(vm_field "$n" 6)" "$LAB_GW" "$RANCHER_HOST" < "$LAB_DIR/guest/base.sh"
done

# 서로 통신 확인 (첫 VM 에서 나머지로 ping)
set -- $VMS
first=$1
for n in $VMS; do
  ip=$(vm_field "$n" 2)
  if vm_sh "$first" ping -c1 -W2 "$ip" >/dev/null 2>&1; then echo "$first → $n ($ip) OK"; else echo "$first → $n ($ip) 실패"; fi
done
info "완료. 다음: ./04-lb-haproxy.sh"
