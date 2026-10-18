#!/usr/bin/env bash
# [Mac] 부록 5.1: lb VM 에 HAProxy 설치와 haproxy.cfg 적용
# haproxy.cfg 를 고친 뒤 다시 실행하면 새 설정으로 바꾸고 재시작한다.
set -euo pipefail
source "$(dirname "$0")/lab.conf.sh"

vm_running lb || die "lb 가 실행 중이 아님. ./02-create-vms.sh lb 먼저"
limactl copy "$LAB_DIR/haproxy.cfg" lb:/tmp/haproxy.cfg
vm_sh lb sudo bash -s < "$LAB_DIR/guest/lb.sh"
info "완료. 다음: 선행 문서 1.1~1.7 (mgmt-1~3), 설치 문서 0~3단계 (mgmt-1)"
