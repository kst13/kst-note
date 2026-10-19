#!/usr/bin/env bash
# 2. RKE2 설치·기동과 확인 (문서 1~6단계, 4.3 반입 경로). 여러 번 실행해도 된다.
# 이미 설치·기동된 노드에서 실행하면 설치는 건너뛰고 확인만 한다.
# 사용: sudo bash 02-install.sh <노드번호 1|2|3>
#   MGMT-1 → (Ready 확인) → MGMT-2 → (Ready 확인) → MGMT-3 순서로 실행한다.
set -uo pipefail
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"
need_root
load_env
set_node "${1:-}"
SRC_DIR=${SRC_DIR:-$(real_home)/rke2-artifacts}
ALREADY=no
systemctl is-active -q rke2-server && ALREADY=yes

if [ "$ALREADY" = no ]; then
  step "사전 조건 (01-prepare.sh 결과)"
  [ -z "$(swapon --show --noheadings)" ] || die "swap이 켜져 있음: 01-prepare.sh 먼저"
  ! systemctl is-active -q firewalld || die "firewalld가 active: 01-prepare.sh 먼저"
  ! systemctl is-active -q docker 2>/dev/null || die "docker가 active: 01-prepare.sh 먼저"
  if ip link show docker0 >/dev/null 2>&1 || iptables -S 2>/dev/null | grep -q 'DOCKER'; then
    die "Docker가 남긴 docker0·iptables 규칙이 있음: sudo reboot 후 다시 실행"
  fi
  if [ -n "${BIND_BASE:-}" ]; then
    mountpoint -q /var/lib/rancher || die "/var/lib/rancher bind mount 안 됨: 01-prepare.sh 먼저"
  fi
  ! ss -lntup | grep -qE "$RKE2_PORTS" || die "RKE2 포트를 다른 프로세스가 사용 중: ss -lntup 확인"
  ok "사전 조건 통과"

  step "반입 파일 ($SRC_DIR → $ARTIFACT_DIR)"
  for f in rke2.linux-amd64.tar.gz rke2-images.linux-amd64.tar.zst sha256sum-amd64.txt install.sh "$RKE2_SELINUX_RPM"; do
    [ -s "$SRC_DIR/$f" ] || [ -s "$ARTIFACT_DIR/$f" ] || die "$f 없음: PC에서 받아 $SRC_DIR 에 두세요 (문서 4.3)"
  done
  install -d -m 755 "$ARTIFACT_DIR"
  if [ "$(readlink -f "$SRC_DIR")" != "$(readlink -f "$ARTIFACT_DIR")" ] && [ -d "$SRC_DIR" ]; then
    cp -u "$SRC_DIR"/* "$ARTIFACT_DIR"/
  fi
  cd "$ARTIFACT_DIR" || die "$ARTIFACT_DIR 이동 실패"
  # Windows에서 받은 install.sh의 CRLF 줄바꿈 정리
  sed -i 's/\r$//' install.sh
  grep -E ' (rke2\.linux-amd64\.tar\.gz|rke2-images\.linux-amd64\.tar\.zst)$' sha256sum-amd64.txt \
    | sha256sum -c --quiet || die "체크섬 불일치: 파일을 다시 받으세요"
  ok "체크섬 일치"

  step "SELinux 정책 RPM"
  rpm -q container-selinux >/dev/null 2>&1 || die "container-selinux 없음: 01-prepare.sh 먼저"
  if ! rpm -q rke2-selinux >/dev/null 2>&1; then
    dnf --disablerepo='*' install -y "./$RKE2_SELINUX_RPM" >/dev/null || die "rke2-selinux 설치 실패"
  fi
  ok "$(rpm -q rke2-selinux)"

  step "시스템 이미지 묶음 (docker.io에서 받지 않게)"
  install -d -m 755 /var/lib/rancher/rke2/agent/images
  install -m 644 rke2-images.linux-amd64.tar.zst /var/lib/rancher/rke2/agent/images/
  ok "/var/lib/rancher/rke2/agent/images/rke2-images.linux-amd64.tar.zst"

  step "RKE2 설치 (tar)"
  cur=$("$RKE2_BIN" --version 2>/dev/null | awk 'NR==1 {print $3}')
  if [ "$cur" != "$RKE2_VERSION" ]; then
    INSTALL_RKE2_VERSION="$RKE2_VERSION" INSTALL_RKE2_METHOD=tar INSTALL_RKE2_TYPE=server \
      INSTALL_RKE2_ARTIFACT_PATH="$ARTIFACT_DIR" sh install.sh >/dev/null || die "install.sh 실패"
    cur=$("$RKE2_BIN" --version 2>/dev/null | awk 'NR==1 {print $3}')
  fi
  [ "$cur" = "$RKE2_VERSION" ] || die "설치 버전 불일치: $cur"
  ok "rke2 $cur ($RKE2_BIN)"

  step "토큰 ($TOKEN_FILE)"
  install -d -m 700 /etc/rancher/rke2
  if [ ! -s "$TOKEN_FILE" ] && [ -s /tmp/rke2-token ]; then
    # MGMT-1에서 scp로 보낸 토큰을 제자리에 둔다
    install -m 600 -o root -g root /tmp/rke2-token "$TOKEN_FILE" && rm -f /tmp/rke2-token
    info "/tmp/rke2-token을 옮김"
  fi
  if [ ! -s "$TOKEN_FILE" ]; then
    if [ "$NODE_NO" = 1 ]; then
      # 새 클러스터용 토큰. 화면에 출력하지 않는다
      (umask 077; openssl rand -hex 32 > "$TOKEN_FILE")
      info "새 bootstrap 토큰 생성"
    else
      printf '\n토큰이 없습니다. MGMT-1에서 실행:\n'
      printf '  sudo install -m 600 -o "$USER" /var/lib/rancher/rke2/server/token /tmp/rke2-token\n'
      printf '  scp /tmp/rke2-token %s@%s:/tmp/rke2-token && rm -f /tmp/rke2-token\n' "$(real_user)" "$NODE_IP"
      die "토큰을 보낸 뒤 이 스크립트를 다시 실행하세요"
    fi
  fi
  chmod 600 "$TOKEN_FILE"; chown root:root "$TOKEN_FILE"
  ok "토큰 파일 준비 (내용은 출력하지 않음)"

  step "config.yaml"
  if [ ! -e "$CFG" ]; then
    {
      [ "$NODE_NO" != 1 ] && printf 'server: https://%s:9345\n' "$JOIN_ADDR"
      cat <<EOF
node-name: $NODE_NAME
node-ip: $NODE_IP
token-file: $TOKEN_FILE
tls-san:
  - $MGMT1_IP
  - $MGMT2_IP
  - $MGMT3_IP
  - $VIP_IP
  - $RANCHER_HOST
cni: canal
ingress-controller: traefik
selinux: true
write-kubeconfig-mode: "$KUBECONFIG_MODE"
etcd-expose-metrics: $ETCD_EXPOSE_METRICS
etcd-snapshot-schedule-cron: "0 */6 * * *"
etcd-snapshot-retention: 20
EOF
    } > "$CFG"
    info "$CFG 작성"
  fi
  chmod 600 "$CFG"
  # 토큰 값이 config에 주석으로라도 들어 있으면 지운다
  if grep -qE '^\s*#?\s*token:' "$CFG"; then
    sed -i -E '/^\s*#?\s*token:/d' "$CFG"
    warn "config에 있던 token 줄을 삭제함. 이 값이 노출됐다면 조인 후 토큰 교체"
  fi
fi

step "config.yaml 검증 (노드 이름은 조인 후 바꿀 수 없다)"
cfg_val() { grep -E "^$1:" "$CFG" | head -1 | sed -E "s/^$1:[[:space:]]*//; s/\"//g"; }
[ "$(cfg_val node-name)" = "$NODE_NAME" ] && ok "node-name: $NODE_NAME" || fail "node-name이 $NODE_NAME 아님: '$(cfg_val node-name)'"
[ "$(cfg_val node-ip)" = "$NODE_IP" ] && ok "node-ip: $NODE_IP" || fail "node-ip가 $NODE_IP 아님: '$(cfg_val node-ip)'"
[ "$(cfg_val token-file)" = "$TOKEN_FILE" ] && ok "token-file" || fail "token-file 경로 확인"
if [ "$NODE_NO" = 1 ]; then
  [ -z "$(cfg_val server)" ] && ok "server: 없음 (첫 노드)" || fail "MGMT-1 config에 server: 가 있음"
else
  [ "$(cfg_val server)" = "https://$JOIN_ADDR:9345" ] && ok "server: https://$JOIN_ADDR:9345" || fail "server: 값 확인: '$(cfg_val server)'"
fi
for s in "$MGMT1_IP" "$MGMT2_IP" "$MGMT3_IP" "$VIP_IP" "$RANCHER_HOST"; do
  grep -qE "^\s*-\s*$s\s*$" "$CFG" || fail "tls-san에 $s 없음"
done
[ "$FAIL" -eq 0 ] || die "config.yaml을 고친 뒤 다시 실행하세요 ($CFG)"

if [ "$NODE_NO" = 1 ]; then
  step "Traefik 설정 (MGMT-1만)"
  TF=/var/lib/rancher/rke2/server/manifests/rke2-traefik-config.yaml
  if [ ! -e "$TF" ]; then
    install -d -m 755 "$(dirname "$TF")"
    cat > "$TF" <<'YAML'
apiVersion: helm.cattle.io/v1
kind: HelmChartConfig
metadata:
  name: rke2-traefik
  namespace: kube-system
spec:
  valuesContent: |-
    deployment:
      kind: DaemonSet
    ports:
      web:
        hostPort: 80
      websecure:
        hostPort: 443
    service:
      type: ClusterIP
YAML
    info "$TF 작성"
  fi
  head -1 "$TF" | grep -q '^apiVersion: helm.cattle.io/v1$' && ok "Traefik 설정 파일 형식" || fail "Traefik 설정 첫 줄 확인: cat -A $TF"
fi

if [ "$ALREADY" = no ]; then
  if [ "$NODE_NO" != 1 ]; then
    step "조인 전 확인"
    tcp_open "$JOIN_ADDR" 9345 || die "$JOIN_ADDR:9345 연결 안 됨"
    ok "$JOIN_ADDR:9345 열림"
    prev=$((NODE_NO - 1))
    printf '\n  mgmt-%s 가 Ready이고 etcd가 정상인지 MGMT-1에서 확인했나요? (kubectl get nodes)\n' "$prev"
    printf '  etcd가 짝수인 동안은 하나만 멈춰도 클러스터가 멈춥니다. 계속할까요? [y/N] '
    read -r ans
    [ "$ans" = y ] || [ "$ans" = Y ] || die "사용자가 중단함"
  fi

  step "rke2-server 기동 (첫 기동은 몇 분 걸린다)"
  systemctl enable --now rke2-server || die "기동 실패: journalctl -u rke2-server -n 100 --no-pager"
  ok "rke2-server 기동 명령 완료"
fi

step "노드 Ready 대기 (최대 20분)"
for _ in $(seq 1 120); do
  st=$($K get node "$NODE_NAME" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
  [ "$st" = True ] && break
  sleep 10
done
if [ "${st:-}" = True ]; then ok "$NODE_NAME Ready"
else fail "$NODE_NAME 가 Ready 아님: journalctl -u rke2-server -n 100 --no-pager"; fi

step "클러스터 상태"
$K get nodes -o wide
echo
$K -n kube-system get pods -l component=etcd -o wide
echo
$K -n kube-system get ds rke2-traefik 2>/dev/null || info "Traefik DaemonSet 아직 없음 (MGMT-1 첫 기동 직후면 잠시 뒤 생성)"
echo
ETCD="$K -n kube-system exec etcd-$NODE_NAME -- etcdctl --cacert /var/lib/rancher/rke2/server/tls/etcd/server-ca.crt --cert /var/lib/rancher/rke2/server/tls/etcd/server-client.crt --key /var/lib/rancher/rke2/server/tls/etcd/server-client.key"
$ETCD member list -w table 2>/dev/null || warn "etcd member list 조회 실패 (기동 직후면 잠시 뒤 다시 실행)"
if $K get nodes -o name 2>/dev/null | grep -vqE '^node/mgmt-[123]$'; then
  warn "mgmt-1~3 외 이름의 노드가 있음: hostname으로 등록된 노드인지 확인"
fi
bad=$($K get pods -A --no-headers 2>/dev/null | grep -vE 'Running|Completed' || true)
if [ -z "$bad" ]; then ok "모든 Pod Running/Completed"
else warn "준비 중이거나 문제 있는 Pod (몇 분 뒤 다시 확인):"; printf '%s\n' "$bad"; fi

case " ${USER_KUBECONFIG_NODES:-} " in
  *" $NODE_NO "*)
    step "사용자 kubeconfig ($(real_user))"
    h=$(real_home); u=$(real_user)
    if [ ! -e "$h/.kube/config" ]; then
      install -d -m 700 -o "$u" -g "$(id -gn "$u")" "$h/.kube"
      install -m 600 -o "$u" -g "$(id -gn "$u")" /etc/rancher/rke2/rke2.yaml "$h/.kube/config"
      info "$h/.kube/config 작성"
    fi
    grep -qF '/var/lib/rancher/rke2/bin' "$h/.bashrc" 2>/dev/null \
      || echo 'export PATH="$HOME/bin:/var/lib/rancher/rke2/bin:$PATH"' >> "$h/.bashrc"
    ok "새 셸에서 sudo 없이 kubectl 사용 가능"
    ;;
esac

summary; rc=$?
printf '\n다음 할 일:\n'
case "$NODE_NO" in
  1) printf '  - MGMT-2에 반입 묶음과 토큰을 보내고 sudo bash 02-install.sh 2\n'
     printf '  - 1대로 Rancher를 먼저 설치하려면 문서 7~10단계 (replicas 1, preferred)\n' ;;
  2) printf '  - 바로 MGMT-3에서 sudo bash 02-install.sh 3 (etcd 2개 상태를 짧게)\n' ;;
  3) printf '  - Rancher values를 replicas 3, antiAffinity required로 바꿔 helm upgrade\n'
     printf '  - 노출된 토큰이 있었다면 토큰 교체, L4 백엔드 3대 활성화\n' ;;
esac
exit "$rc"
