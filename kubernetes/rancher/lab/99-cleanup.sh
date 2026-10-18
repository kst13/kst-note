#!/usr/bin/env bash
# [Mac] 부록 10장: 실습 VM, /app 디스크, Mac 쪽 실습 흔적 삭제
# 되돌릴 수 없으므로 delete 를 직접 입력해야 진행한다.
# socket_vmnet, sudoers, networks.yaml 은 다른 Lima VM 도 쓸 수 있어 남겨 둔다.
set -euo pipefail
source "$(dirname "$0")/lab.conf.sh"

ALL=$(resolve_vms all)
echo "삭제 대상 VM: $ALL"
echo "삭제 대상 디스크: 각 VM 의 <이름>-app"
echo "Mac: $LAB_HOME, /etc/hosts 의 $RANCHER_HOST 줄, 키체인의 Lab Internal Root CA"
read -r -p '진행하려면 delete 입력: ' ANSWER
[ "$ANSWER" = delete ] || die "취소"

for n in $ALL; do
  if vm_exists "$n"; then limactl delete --force "$n"; fi
done
for n in $ALL; do
  if limactl disk ls 2>/dev/null | awk 'NR > 1 { print $1 }' | grep -qx "${n}-app"; then limactl disk delete "${n}-app"; fi
done

security delete-certificate -c "Lab Internal Root CA" "$HOME/Library/Keychains/login.keychain-db" 2>/dev/null || true
sudo sed -i '.bak' "/[[:space:]]${RANCHER_HOST//./\\.}\$/d" /etc/hosts
rm -rf "$LAB_HOME"
info "완료. 이미지 캐시까지 지우려면: limactl prune"
