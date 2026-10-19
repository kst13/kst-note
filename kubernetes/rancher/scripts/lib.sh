# 공통 함수. 00·01·02 스크립트가 source 한다. 단독 실행하지 않는다.

PASS=0; WARN=0; FAIL=0
ok()   { printf '  [OK]   %s\n' "$*"; PASS=$((PASS + 1)); }
warn() { printf '  [WARN] %s\n' "$*"; WARN=$((WARN + 1)); }
fail() { printf '  [FAIL] %s\n' "$*"; FAIL=$((FAIL + 1)); }
info() { printf '         %s\n' "$*"; }
step() { printf '\n== %s\n' "$*"; }
die()  { printf '\n[중단] %s\n' "$*" >&2; exit 1; }

summary() {
  printf '\n결과: OK %d / WARN %d / FAIL %d\n' "$PASS" "$WARN" "$FAIL"
  [ "$FAIL" -eq 0 ]
}

need_root() {
  [ "$(id -u)" -eq 0 ] || die "sudo로 실행하세요: sudo bash $0 <노드번호>"
}

# cluster.env를 읽고 필수 값이 비었는지 확인
load_env() {
  local f="$SCRIPT_DIR/cluster.env" v
  [ -f "$f" ] || die "cluster.env 없음: cp cluster.env.example cluster.env 후 값을 채우세요"
  # shellcheck source=/dev/null
  source "$f"
  for v in RKE2_VERSION RANCHER_HOST VIP_IP MGMT1_IP MGMT2_IP MGMT3_IP JOIN_ADDR; do
    [ -n "${!v:-}" ] || die "cluster.env의 $v 값이 비어 있음"
  done
  case "$RANCHER_HOST" in *example*) die "cluster.env에 예시 값이 남아 있음: RANCHER_HOST" ;; esac
}

# 노드 번호로 이름·IP를 정하고, 이 서버가 맞는지 확인
set_node() {
  local v
  NODE_NO=${1:-}
  case "$NODE_NO" in
    1|2|3) ;;
    *) die "노드 번호를 주세요: 1, 2, 3 중 하나 (예: sudo bash $0 2)" ;;
  esac
  NODE_NAME="mgmt-$NODE_NO"
  v="MGMT${NODE_NO}_IP"
  NODE_IP=${!v}
  ip -o -4 addr show | awk '{print $4}' | cut -d/ -f1 | grep -qx "$NODE_IP" \
    || die "이 서버에 $NODE_IP 주소가 없음: 노드 번호가 맞는지 확인하세요"
  printf '대상: %s (%s), hostname %s\n' "$NODE_NAME" "$NODE_IP" "$(hostname)"
}

# sudo로 실행한 원래 계정과 그 홈 디렉터리
real_user() { printf '%s' "${SUDO_USER:-$(id -un)}"; }
real_home() { getent passwd "$(real_user)" | cut -d: -f6; }

tcp_open() { timeout 5 bash -c "</dev/tcp/$1/$2" 2>/dev/null; }
http_code() { curl -s -o /dev/null --max-time 8 -w '%{http_code}' "$1" 2>/dev/null || true; }

RKE2_BIN=/usr/local/bin/rke2
K="/var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml"
SOCK=unix:///run/k3s/containerd/containerd.sock
CFG=/etc/rancher/rke2/config.yaml
TOKEN_FILE=/etc/rancher/rke2/server-token
RKE2_PORTS=':(80|443|2379|2380|6443|9345|9099|10250)\s'
