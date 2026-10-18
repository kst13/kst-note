#!/usr/bin/env bash
# [Mac] 부록 3장: /app 디스크와 VM 생성 후 시작
# 사용법: ./02-create-vms.sh [base|dev|all|VM이름...]   기본값 base (lb, mgmt-1~3)
# 이미 있는 디스크와 VM 은 건너뛴다.
set -euo pipefail
source "$(dirname "$0")/lab.conf.sh"

TEMPLATE="$LAB_DIR/rocky9-node.yaml"
limactl validate "$TEMPLATE" >/dev/null
VMS=$(resolve_vms base "$@")

for n in $VMS; do
  cpus=$(vm_field "$n" 3); mem=$(vm_field "$n" 4); disk=$(vm_field "$n" 5); app=$(vm_field "$n" 6)

  if [ "$app" != 0 ] && ! limactl disk ls 2>/dev/null | awk 'NR > 1 { print $1 }' | grep -qx "${n}-app"; then
    info "$n: /app 디스크 ${app}GiB 생성"
    limactl disk create "${n}-app" --size "${app}GiB"
  fi

  if ! vm_exists "$n"; then
    set_expr=".cpus = ${cpus} | .memory = \"${mem}\" | .disk = \"${disk}\""
    [ "$app" = 0 ] || set_expr="$set_expr | .additionalDisks = [{\"name\": \"${n}-app\", \"format\": false}]"
    info "$n: VM 생성 (${cpus} vCPU, ${mem}, ${disk})"
    limactl create --name "$n" --tty=false --set "$set_expr" "$TEMPLATE"
  fi

  if ! vm_running "$n"; then
    info "$n: 시작 (처음에는 이미지 다운로드로 몇 분 걸림)"
    limactl start --tty=false "$n"
  fi
done

limactl list
info "완료. 다음: ./03-configure-vms.sh $*"
