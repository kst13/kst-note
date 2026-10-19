#!/usr/bin/env bash
# 0. 방화벽·네트워크 확인. 읽기 전용이라 언제 실행해도 된다.
# 사용: sudo bash 00-check-network.sh <노드번호 1|2|3>
set -uo pipefail
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"
load_env
set_node "${1:-}"

step "외부 HTTPS: 항상 필요 (컨테이너 이미지·차트)"
# 응답 코드가 나오면 열림. 000이면 차단
for h in registry-1.docker.io auth.docker.io production.cloudflare.docker.com \
         production.cloudfront.docker.com releases.rancher.com; do
  c=$(http_code "https://$h")
  if [ "$c" != "000" ]; then ok "$h ($c)"; else fail "$h 차단"; fi
done

step "외부 HTTPS: 온라인 설치 경로(4.1)에만 필요. 막혀 있으면 4.3 반입 경로로 설치"
for h in rpm.rancher.io get.rke2.io github.com release-assets.githubusercontent.com get.helm.sh; do
  c=$(http_code "https://$h")
  if [ "$c" != "000" ]; then ok "$h ($c)"; else warn "$h 차단"; fi
done

step "Docker Hub 실제 이미지 받기 (RKE2가 떠 있을 때만)"
# 연결 테스트가 통과해도 CDN에서 큰 파일 받기가 막힐 수 있어 실제로 받아 본다
if [ "$(id -u)" -ne 0 ]; then
  info "sudo로 실행해야 확인 가능해 건너뜀"
elif systemctl is-active -q rke2-server; then
  if timeout 300 /var/lib/rancher/rke2/bin/crictl -r "$SOCK" pull docker.io/library/busybox:1.37 >/dev/null 2>&1; then
    ok "docker.io/library/busybox:1.37 받기 성공"
  else
    fail "docker.io 이미지 받기 실패: CDN 차단·지연 의심"
  fi
else
  info "rke2-server가 아직 없어 건너뜀"
fi

step "DNS"
resolved=$(getent hosts "$RANCHER_HOST" | awk '{print $1}' | head -1)
if [ "$resolved" = "$VIP_IP" ]; then ok "$RANCHER_HOST → $VIP_IP"
elif [ -n "$resolved" ]; then warn "$RANCHER_HOST → $resolved (VIP $VIP_IP 아님)"
else warn "$RANCHER_HOST 이름 풀이 안 됨: DNS 등록 전이면 정상"; fi

step "L4 VIP ($VIP_IP)"
if tcp_open "$VIP_IP" 443; then ok "VIP 443 열림"; else warn "VIP 443 닫힘: L4 준비 전이면 정상"; fi
if tcp_open "$VIP_IP" 9345; then ok "VIP 9345 열림 (조인 주소로 VIP 사용 가능)"
else info "VIP 9345 닫힘: JOIN_ADDR는 MGMT-1 IP를 쓴다"; fi

step "MGMT 서버 간 포트 (상대 서버에 RKE2가 떠 있어야 열림)"
for n in 1 2 3; do
  [ "$n" = "$NODE_NO" ] && continue
  v="MGMT${n}_IP"; peer=${!v}
  for p in 9345 6443 2379 2380 10250; do
    if tcp_open "$peer" "$p"; then ok "mgmt-$n $peer:$p"
    else info "mgmt-$n $peer:$p 닫힘 (그 서버 설치 전이면 정상)"; fi
  done
done
if [ "$NODE_NO" != 1 ]; then
  # MGMT-2·3은 조인 주소의 9345가 열려 있어야 설치할 수 있다
  if tcp_open "$JOIN_ADDR" 9345; then ok "조인 주소 $JOIN_ADDR:9345 열림"
  else fail "조인 주소 $JOIN_ADDR:9345 닫힘: MGMT-1 기동·방화벽 확인"; fi
fi

if [ -n "${NEXUS_ADDR:-}" ]; then
  step "Nexus ($NEXUS_ADDR)"
  c=$(http_code "http://$NEXUS_ADDR/v2/")
  case "$c" in
    200|401) ok "Nexus /v2/ 응답 $c" ;;
    *) warn "Nexus /v2/ 응답 $c" ;;
  esac
fi

step "시간 동기화"
if chronyc tracking 2>/dev/null | grep -q 'Leap status *: Normal'; then ok "chrony 동기화 정상"
else warn "chrony 동기화 확인 필요: chronyc tracking"; fi

summary
