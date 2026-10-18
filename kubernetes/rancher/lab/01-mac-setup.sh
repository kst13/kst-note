#!/usr/bin/env bash
# [Mac] 부록 2장 + 5.2: Lima, socket_vmnet, networks.yaml, sudoers, /etc/hosts
# 여러 번 실행해도 된다. 이미 된 단계는 건너뛴다.
set -euo pipefail
source "$(dirname "$0")/lab.conf.sh"

[ "$(uname -s)" = Darwin ] || die "macOS 전용 스크립트"
command -v brew >/dev/null || die "Homebrew 가 없음. https://brew.sh 안내대로 먼저 설치"

# 2.1 Lima
if ! command -v limactl >/dev/null; then
  info "Lima 설치"
  brew install lima
fi
limactl --version | grep -qE 'version [2-9]\.' || die "Lima 2.0 이상 필요: $(limactl --version)"

# 2.2 socket_vmnet. root 소유 경로로 복사하고, 내용이 다를 때만 다시 복사
brew list socket_vmnet >/dev/null 2>&1 || { info "socket_vmnet 설치"; brew install socket_vmnet; }
SRC="$(brew --prefix)/opt/socket_vmnet/bin/socket_vmnet"
DST=/opt/socket_vmnet/bin/socket_vmnet
if ! cmp -s "$SRC" "$DST" 2>/dev/null; then
  info "socket_vmnet 을 $DST 로 복사 (sudo)"
  sudo mkdir -p /opt/socket_vmnet/bin
  sudo install -o root -g wheel -m 755 "$SRC" "$DST"
fi

# 2.3 networks.yaml. 없으면 limactl sudoers 로 기본값 생성
NW="$LIMA_HOME_DIR/_config/networks.yaml"
[ -f "$NW" ] || limactl sudoers >/dev/null
[ -f "$NW" ] || die "$NW 생성 실패"

if grep -q "dhcpEnd: ${LAB_DHCP_END_DEFAULT}" "$NW" || grep -qE '^ *vde(Switch|VMNet):' "$NW"; then
  RUNNING=$(limactl list --format '{{.Name}} {{.Status}}' 2>/dev/null | awk '$2 == "Running" { print $1 }')
  [ -z "$RUNNING" ] || die "실행 중인 VM 을 먼저 끄세요: $RUNNING"
  BAK="$NW.bak.$(date +%Y%m%d%H%M%S)"
  info "networks.yaml 수정 (백업: $BAK)"
  cp "$NW" "$BAK"
  sed -i '' \
    -e "s/^\( *dhcpEnd: \)${LAB_DHCP_END_DEFAULT//./\\.}/\1${LAB_DHCP_END}/" \
    -e '/^ *vdeSwitch:/d' \
    -e '/^ *vdeVMNet:/d' \
    "$NW"
  diff "$BAK" "$NW" || true
fi
grep -q "dhcpEnd: ${LAB_DHCP_END}" "$NW" || die "networks.yaml 의 shared dhcpEnd 가 ${LAB_DHCP_END} 가 아님. 직접 확인"

# 2.4 sudoers. networks.yaml 을 확정한 뒤, 내용이 다를 때만 설치
TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT
limactl sudoers > "$TMP"
grep -q -- "--vmnet-dhcp-end=${LAB_DHCP_END}" "$TMP" || die "생성된 sudoers 에 dhcp-end ${LAB_DHCP_END} 가 없음"
# limactl 이 일반 사용자 권한으로 이 파일을 읽어 비교하므로 444 (440 이면 permission denied)
if ! sudo cmp -s "$TMP" /etc/sudoers.d/lima 2>/dev/null; then
  info "sudoers 설치 (sudo)"
  sudo visudo -cf "$TMP"
  sudo install -o root -g wheel -m 444 "$TMP" /etc/sudoers.d/lima
elif [ ! -r /etc/sudoers.d/lima ]; then
  info "sudoers 권한을 444 로 변경 (sudo)"
  sudo chmod 444 /etc/sudoers.d/lima
fi

# 5.2 Mac /etc/hosts
if ! grep -q "[[:space:]]${RANCHER_HOST//./\\.}\$" /etc/hosts; then
  info "/etc/hosts 에 ${LB_IP} ${RANCHER_HOST} 추가 (sudo)"
  echo "${LB_IP} ${RANCHER_HOST}" | sudo tee -a /etc/hosts >/dev/null
fi

mkdir -p "$LAB_HOME"
info "완료. 다음: ./02-create-vms.sh"
