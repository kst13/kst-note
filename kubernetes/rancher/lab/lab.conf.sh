# Lima 실습 환경 설정. 모든 스크립트가 이 파일을 읽는다.
# 값을 바꾸면 rocky9-node.yaml 의 hostResolver 와 haproxy.cfg 의 IP 도 같이 바꾼다.

# 실습망 (Lima shared 망)
LAB_GW=192.168.105.1
LAB_DHCP_END=192.168.105.49
LAB_DHCP_END_DEFAULT=192.168.105.254

# Rancher 도메인과 lb IP
RANCHER_HOST=rancher.lab.internal
LB_IP=192.168.105.108

# VM 목록: 이름 IP vCPU 메모리 루트디스크 /app디스크(GiB, 0=없음)
LAB_VMS="
lb     192.168.105.108 1 1GiB 10GiB 0
mgmt-1 192.168.105.109 4 8GiB 30GiB 40
mgmt-2 192.168.105.110 4 8GiB 30GiB 40
mgmt-3 192.168.105.111 4 8GiB 30GiB 40
dev-1  192.168.105.56  2 6GiB 30GiB 40
dev-2  192.168.105.57  2 6GiB 30GiB 40
dev-3  192.168.105.58  2 6GiB 30GiB 40
"

# 그룹 이름 → VM 이름
LAB_GROUP_BASE="lb mgmt-1 mgmt-2 mgmt-3"
LAB_GROUP_MGMT="mgmt-1 mgmt-2 mgmt-3"
LAB_GROUP_DEV="dev-1 dev-2 dev-3"

# Mac 쪽 실습 파일 위치. 인증서처럼 git 에 넣지 않을 파일을 여기에 둔다 (vault 밖)
LAB_HOME="$HOME/lima-lab"
LIMA_HOME_DIR="${LIMA_HOME:-$HOME/.lima}"

LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

die() { echo "오류: $*" >&2; exit 1; }
info() { echo "==> $*"; }

# vm_field <이름> <열 번호>  열: 2=IP 3=vCPU 4=메모리 5=루트디스크 6=/app디스크
vm_field() {
  echo "$LAB_VMS" | awk -v n="$1" -v c="$2" '$1 == n { print $c }'
}

# 인자(VM 이름 또는 base/mgmt/dev/all)를 VM 이름 목록으로 바꾼다. 인자가 없으면 기본값 사용
resolve_vms() {
  local default="$1"; shift
  local args="$*" out="" a
  [ -n "$args" ] || args="$default"
  for a in $args; do
    case "$a" in
      base) out="$out $LAB_GROUP_BASE" ;;
      mgmt) out="$out $LAB_GROUP_MGMT" ;;
      dev)  out="$out $LAB_GROUP_DEV" ;;
      all)  out="$out $LAB_GROUP_BASE $LAB_GROUP_DEV" ;;
      *)    [ -n "$(vm_field "$a" 2)" ] || die "lab.conf.sh 에 없는 VM: $a"; out="$out $a" ;;
    esac
  done
  echo $out
}

vm_exists()  { limactl list -q 2>/dev/null | grep -qx "$1"; }
vm_running() { [ "$(limactl list --format '{{.Status}}' "$1" 2>/dev/null)" = "Running" ]; }

# VM 안에서 명령 실행. Mac 현재 폴더가 VM 에 없으므로 작업 폴더를 / 로 고정
vm_sh() { local n="$1"; shift; limactl shell --workdir / "$n" "$@"; }
