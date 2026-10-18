# Lima 실습 스크립트

[[부록. Lima 실습 환경]]의 수동 절차를 스크립트로 묶은 것이다. 다른 Mac에서 같은 실습 환경을 다시 만들 때 쓴다. 각 단계가 무엇을 하는지는 부록의 같은 절을 본다.

## 다른 Mac에서 시작하기

```bash
# [Mac] vault 저장소를 받고 이 폴더로 이동
git clone <vault 저장소 주소> kst-note
cd "kst-note/kubernetes/rancher/lab"

./01-mac-setup.sh          # 부록 2장, 5.2: Lima, socket_vmnet, networks.yaml, sudoers, /etc/hosts (sudo 비밀번호를 물음)
./02-create-vms.sh         # 부록 3장: lb, mgmt-1~3 생성과 시작
./03-configure-vms.sh      # 부록 4장: 고정 IP, /app 디스크
./04-lb-haproxy.sh         # 부록 5.1: HAProxy
```

여기까지 하면 선행 문서와 설치 문서를 시작할 수 있다. 나머지는 설치 진행 중 필요한 시점에 실행한다.

| 스크립트 | 실행 시점 | 하는 일 |
|---|---|---|
| `06-copy-join-token.sh` | 설치 4단계 뒤, 6단계 전 | mgmt-1 토큰을 mgmt-2, mgmt-3에 복사 (부록 7.4) |
| `05-lab-ca.sh` | 설치 8단계 전 | mgmt-1에서 실습 CA 생성, MGMT와 Mac 키체인에 신뢰 등록 (부록 7.5) |
| `02-create-vms.sh dev` → `03-configure-vms.sh dev` → `05-lab-ca.sh dev` | Rancher 설치 뒤 | DEV VM 생성, 기본 설정, CA 신뢰 (부록 8장) |
| `99-cleanup.sh` | 실습을 끝낼 때 | VM, 디스크, Mac의 실습 흔적 삭제 (부록 10장) |

번호는 만든 순서이고, 실행 순서는 위 표를 따른다(06이 05보다 먼저).

## 파일

| 파일 | 내용 |
|---|---|
| `lab.conf.sh` | VM 이름, IP, CPU, 메모리, 디스크, 도메인. 모든 스크립트가 읽는다 |
| `rocky9-node.yaml` | Lima VM 템플릿 (부록 3.1) |
| `haproxy.cfg` | lb의 HAProxy 설정 (부록 5.1) |
| `guest/*.sh` | VM 안에서 실행되는 부분. Mac 스크립트가 표준입력으로 넘긴다 |
| `.gitignore` | 인증서, 키, 토큰, kubeconfig가 커밋되지 않게 막는다 |

## 사용 규칙

- 모든 스크립트는 여러 번 실행해도 된다. 이미 된 단계는 건너뛴다. 중간에 실패하면 원인을 고치고 같은 스크립트를 다시 실행한다.
- 대상 VM은 인자로 고른다: `base`(lb, mgmt-1~3), `mgmt`, `dev`, `all`, 또는 VM 이름. 인자가 없으면 각 스크립트의 기본값을 쓴다.
- IP나 도메인을 바꾸려면 `lab.conf.sh`, `rocky9-node.yaml`의 `hostResolver`, `haproxy.cfg` 세 곳을 같이 고친다.
- 인증서와 키는 mgmt-1의 `~/lab-ca`, Mac의 `~/lima-lab`에만 둔다. 이 폴더에 복사하지 않는다.
- Apple Silicon Mac 기준이다. Intel Mac에서는 템플릿이 x86_64 이미지를 고르므로 그대로 동작할 것으로 보이지만 확인하지 않았다. 이 경우 부록 7.3의 arm64 변경은 필요 없다.

## 검증 상태

스크립트 문법(`bash -n`)과 템플릿(`limactl validate`)만 확인했다. 실제 VM에서 끝까지 실행해 본 것은 아니다. 처음 실행할 때는 부록의 각 절 "정상" 기준과 결과를 대조한다.
