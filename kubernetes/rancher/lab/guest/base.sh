#!/usr/bin/env bash
# [VM, root] 03-configure-vms.sh 가 표준입력으로 넘겨 실행한다.
# 인자: <실습 IP> <app 디스크 GiB, 0=없음> <게이트웨이> <Rancher FQDN>
set -euo pipefail
LAB_IP=$1; APP_GIB=$2; GW=$3; RANCHER_HOST=$4

# 4.1 lima0 고정 IP
CON=$(nmcli -g GENERAL.CONNECTION device show lima0 2>/dev/null || true)
[ -n "$CON" ] || { echo "lima0 인터페이스 없음: networks.yaml 과 템플릿 networks 확인"; exit 1; }
if [ "$(nmcli -g ipv4.method con show "$CON")" != manual ] || ! nmcli -g ipv4.addresses con show "$CON" | grep -qx "${LAB_IP}/24"; then
  echo "  lima0 → ${LAB_IP}/24"
  nmcli con mod "$CON" ipv4.method manual ipv4.addresses "${LAB_IP}/24" ipv4.gateway "$GW" ipv4.ignore-auto-dns yes
  nmcli con up "$CON" >/dev/null
fi
# 다음 부팅부터 cloud-init 이 네트워크 설정을 다시 쓰지 않도록 막음
echo 'network: {config: disabled}' > /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg

# 4.2 /app 디스크
if [ "$APP_GIB" != 0 ] && ! grep -qE '[[:space:]]/app[[:space:]]' /etc/fstab; then
  WANT=$((APP_GIB * 1024 * 1024 * 1024))
  CAND=""
  # 크기가 정확히 APP_GIB 이고, 파티션과 파일시스템이 없는 디스크만 후보
  for d in $(lsblk -dbnp -o NAME,SIZE,TYPE | awk -v w="$WANT" '$3 == "disk" && $2 == w { print $1 }'); do
    [ "$(lsblk -n "$d" | wc -l)" -eq 1 ] || continue
    [ -z "$(blkid -o value -s TYPE "$d" || true)" ] || continue
    CAND="$CAND $d"
  done
  set -- $CAND
  [ $# -eq 1 ] || { echo "/app 후보 디스크가 1개가 아님: '$CAND'"; lsblk; exit 1; }
  echo "  $1 → xfs 포맷, /app 마운트"
  mkfs.xfs -q "$1"
  mkdir -p /app
  echo "UUID=$(blkid -s UUID -o value "$1") /app xfs defaults 0 0" >> /etc/fstab
  systemctl daemon-reload
  mount /app
fi

# 결과
ip -br addr show lima0
[ "$APP_GIB" = 0 ] || df -h /app | tail -1
getent hosts "$RANCHER_HOST" || echo "  경고: $RANCHER_HOST 를 해석하지 못함 (템플릿 hostResolver 확인)"
echo "  SELinux: $(getenforce)"
