#!/usr/bin/env bash
# 1. OS 사전 작업 처리와 확인 (문서 1. 설치 선행 1.1~1.7). 여러 번 실행해도 된다.
# 사용: sudo bash 01-prepare.sh <노드번호 1|2|3>
set -uo pipefail
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"
need_root
load_env
set_node "${1:-}"
REBOOT_REASONS=()

step "1.1 firewalld 비활성화"
if systemctl list-unit-files firewalld.service >/dev/null 2>&1 && systemctl is-enabled -q firewalld 2>/dev/null; then
  systemctl disable --now firewalld
fi
if systemctl is-active -q firewalld; then fail "firewalld가 아직 active"; else ok "firewalld inactive"; fi

step "1.2 NetworkManager: CNI 인터페이스 관리 제외"
NM_CONF=/etc/NetworkManager/conf.d/rke2-canal.conf
NM_WANT='[keyfile]
unmanaged-devices=interface-name:flannel*;interface-name:cali*;interface-name:tunl*;interface-name:vxlan.calico;interface-name:vxlan-v6.calico;interface-name:wireguard.cali;interface-name:wg-v6.cali'
if [ "$(cat "$NM_CONF" 2>/dev/null)" != "$NM_WANT" ]; then
  install -d /etc/NetworkManager/conf.d
  printf '%s\n' "$NM_WANT" > "$NM_CONF"
  systemctl reload NetworkManager 2>/dev/null || true
  info "$NM_CONF 작성"
fi
ok "NetworkManager 설정 적용됨"

step "1.2 nm-cloud-setup 비활성화"
if rpm -q NetworkManager-cloud-setup >/dev/null 2>&1; then
  if systemctl is-enabled -q nm-cloud-setup.service 2>/dev/null || systemctl is-enabled -q nm-cloud-setup.timer 2>/dev/null; then
    systemctl disable --now nm-cloud-setup.service nm-cloud-setup.timer
    REBOOT_REASONS+=("nm-cloud-setup이 추가한 라우팅 규칙 제거")
  fi
  ok "nm-cloud-setup disabled"
else
  ok "nm-cloud-setup 미설치"
fi

step "1.4 swap 비활성화"
swapoff -a
if grep -qE '^[^#].*\sswap\s' /etc/fstab; then
  cp -n /etc/fstab /etc/fstab.bak
  sed -i '/\sswap\s/s/^\([^#]\)/#\1/' /etc/fstab
  info "/etc/fstab의 swap 줄 주석 처리 (원본 /etc/fstab.bak)"
fi
if [ -z "$(swapon --show --noheadings)" ]; then ok "swap 꺼짐"; else fail "swap이 아직 켜져 있음"; fi

step "1.5 Docker 비활성화"
if systemctl list-unit-files docker.service >/dev/null 2>&1 && systemctl cat docker.service >/dev/null 2>&1; then
  if systemctl is-active -q docker && [ -n "$(docker ps -q 2>/dev/null)" ]; then
    die "실행 중인 Docker 컨테이너가 있음: docker ps 확인 후 옮기고 다시 실행"
  fi
  # containerd.service는 Docker용이다. RKE2의 containerd는 rke2-server가 직접 띄운다
  units="docker docker.socket"
  systemctl cat containerd.service >/dev/null 2>&1 && units="$units containerd"
  # shellcheck disable=SC2086
  systemctl disable --now $units 2>/dev/null || true
  if systemctl is-active -q docker; then fail "docker가 아직 active"; else ok "docker inactive, disabled"; fi
else
  ok "Docker 미설치"
fi
if ip link show docker0 >/dev/null 2>&1; then REBOOT_REASONS+=("docker0 브리지 남음"); fi
if iptables -S 2>/dev/null | grep -q 'DOCKER'; then
  REBOOT_REASONS+=("Docker가 남긴 iptables 규칙(DOCKER 체인, FORWARD DROP)")
elif iptables -S FORWARD 2>/dev/null | grep -q '^-P FORWARD DROP'; then
  warn "FORWARD 기본 정책이 DROP인데 Docker 흔적은 없음: 다른 설정이 원인인지 확인"
fi

step "외부 저장소 끄기 (막힌 저장소 때문에 dnf가 실패하지 않게)"
enabled=$(dnf -q repolist --enabled 2>/dev/null | awk 'NR>1 {print $1}')
for r in ${DISABLE_REPOS:-}; do
  if printf '%s\n' "$enabled" | grep -qx "$r"; then
    dnf config-manager --set-disabled "$r" >/dev/null && info "$r 끔"
  fi
done
ok "켜진 저장소: $(dnf -q repolist --enabled 2>/dev/null | awk 'NR>1 {printf "%s ", $1}')"

step "container-selinux (rke2-selinux 의존 패키지)"
if ! rpm -q container-selinux >/dev/null 2>&1; then
  dnf --disablerepo='*' --enablerepo=baseos,appstream install -y container-selinux >/dev/null 2>&1 || true
fi
if rpm -q container-selinux >/dev/null 2>&1; then ok "$(rpm -q container-selinux)"
else fail "container-selinux 설치 실패: PC에서 Rocky 9 AppStream RPM 반입 필요"; fi

step "1.6 bind mount"
if [ -z "${BIND_BASE:-}" ]; then
  info "BIND_BASE가 비어 있어 건너뜀"
else
  parent=$(dirname "$BIND_BASE")
  if ! grep -q "^$BIND_BASE/rancher " /etc/fstab; then
    mountpoint -q "$parent" || die "$parent 가 마운트되지 않음"
    # 이미 데이터가 있으면 마운트 순간 가려진다. RKE2 설치 전에만 새로 등록한다
    [ ! -e /var/lib/rancher/rke2 ] || die "/var/lib/rancher/rke2가 이미 있음: 설치 후에는 bind mount를 새로 걸지 않는다"
    install -d "$BIND_BASE/rancher" "$BIND_BASE/kubelet" "$BIND_BASE/log-pods"
    install -d /var/lib/rancher /var/lib/kubelet /var/log/pods
    cp -n /etc/fstab /etc/fstab.bak
    cat >> /etc/fstab <<EOT
$BIND_BASE/rancher  /var/lib/rancher  none  defaults,bind,x-systemd.requires-mounts-for=$parent  0 0
$BIND_BASE/kubelet  /var/lib/kubelet  none  defaults,bind,x-systemd.requires-mounts-for=$parent  0 0
$BIND_BASE/log-pods /var/log/pods     none  defaults,bind,x-systemd.requires-mounts-for=$parent  0 0
EOT
    systemctl daemon-reload
    mount -a
    info "/etc/fstab에 bind mount 3줄 등록"
  fi
  for t in /var/lib/rancher /var/lib/kubelet /var/log/pods; do
    if mountpoint -q "$t"; then ok "$t ← $(findmnt -n -o SOURCE -T "$t")"
    else fail "$t 마운트 안 됨: mount -a 확인"; fi
  done
fi

step "SELinux"
mode=$(getenforce 2>/dev/null || echo 없음)
info "SELinux: $mode (3대가 같아야 한다)"
ok "SELinux 확인"

step "1.7 RKE2 포트·잔재"
if systemctl is-active -q rke2-server; then
  ok "rke2-server 실행 중 (이미 설치된 노드)"
elif ss -lntup | grep -qE "$RKE2_PORTS"; then
  fail "RKE2가 쓸 포트를 다른 프로세스가 사용 중: ss -lntup 확인"
else
  ok "RKE2 포트 비어 있음"
fi

summary; rc=$?
if [ "${#REBOOT_REASONS[@]}" -gt 0 ]; then
  printf '\n[재부팅 필요]\n'
  for r in "${REBOOT_REASONS[@]}"; do printf '  - %s\n' "$r"; done
  printf '  sudo reboot 후 이 스크립트를 다시 실행해 확인하세요.\n'
  if systemctl is-active -q rke2-server; then
    printf '  이 노드는 RKE2가 실행 중이다. 클러스터 노드는 한 대씩만 재부팅한다.\n'
  fi
  exit 2
fi
exit "$rc"
