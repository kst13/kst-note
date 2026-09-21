# k3d 설치

공식 홈페이지: https://k3d.io

## 사전 필요사항

- Docker (v20.10.5 이상)
- kubectl — https://kubernetes.io/docs/tasks/tools/#kubectl

helm은 k3d 요구사항이 아님. Rancher 설치 단계에서만 필요.

## 설치 방법

설치 스크립트가 GitHub 릴리스에서 바이너리를 받아 `/usr/local/bin/k3d`에 둔다. wget 또는 curl 중 하나만 실행.

### 최신 버전

```bash
wget -q -O - https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
# 또는
curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
```

### 특정 버전

```bash
wget -q -O - https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | TAG=v5.0.0 bash
# 또는
curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | TAG=v5.0.0 bash
```

### 그 외 방법

| 방법 | 명령 |
| --- | --- |
| Homebrew (macOS·Linux) | `brew install k3d` |
| Chocolatey / Scoop (Windows) | `choco install k3d` / `scoop install k3d` |
| 바이너리 직접 | GitHub Releases에서 OS별 파일 다운로드 후 PATH에 배치 |

### 확인

```bash
k3d version        # k3d 버전과 기본 k3s 이미지 버전이 함께 나옴
```

## Quick Start

```bash
k3d cluster create mycluster
```

"mycluster라는 이름으로 클러스터 생성". 옵션이 없으므로 기본값 적용.

- server 노드 1개 (컨트롤 플레인 + 워커 겸임)
- agent 노드 0개
- loadbalancer 컨테이너 1개 (자동)
- API 포트는 임의의 빈 포트

생성이 끝나면 `~/.kube/config`에 `k3d-mycluster` context가 추가되고 현재 context로 전환된다. 그래서 바로 kubectl 사용 가능.

```bash
kubectl get nodes
# NAME                     STATUS   ROLES                  AGE   VERSION
# k3d-mycluster-server-0   Ready    control-plane,master   30s   v1.35.5+k3s1
```

### kubeconfig 다시 병합하기

`k3d cluster create`가 자동으로 하는 작업. `~/.kube/config`를 지웠거나 context가 다른 클러스터로 가 있을 때만 직접 실행.

```bash
k3d kubeconfig merge mycluster --kubeconfig-switch-context
```

### Quick Start를 설정 파일로 쓰면

기본값이라 이름만 적으면 동일.

```yaml
apiVersion: k3d.io/v1alpha5
kind: Simple
metadata:
  name: mycluster
```

```bash
k3d cluster create --config k3d-mycluster.yaml
```

## 기본값 전체 (명령 한 줄 뒤에 숨어 있는 것)

```yaml
apiVersion: k3d.io/v1alpha5
kind: Simple
metadata:
  name: mycluster
servers: 1                 # server 1개
agents: 0                  # agent 없음
image: rancher/k3s:v1.35.5-k3s1   # 생략하면 k3d 5.9.0 의 기본값. k3d 버전마다 달라짐
kubeAPI:
  hostIP: "0.0.0.0"        # 모든 인터페이스에서 API 접근 가능 (로컬 전용이면 127.0.0.1)
  hostPort: ""             # 빈 값 = 임의의 빈 포트
ports: []                  # 호스트로 매핑하는 포트 없음 → Ingress 외부 접근 불가
options:
  k3d:
    wait: true             # server 가 뜰 때까지 대기
    timeout: "0s"          # 무한 대기
    disableLoadbalancer: false   # serverlb 컨테이너 생성
    disableImageVolume: false    # image import 용 볼륨 생성
    disableRollback: false       # 실패 시 자동 롤백
  k3s:
    extraArgs: []          # k3s 에 넘기는 추가 인자 없음 → Traefik, ServiceLB, local-path 전부 켜짐
    nodeLabels: []
  kubeconfig:
    updateDefaultKubeconfig: true   # ~/.kube/config 에 병합
    switchCurrentContext: true      # 현재 context 전환
```

## 자주 쓰는 옵션

전체 목록: `k3d cluster create --help` 또는 https://k3d.io/stable/usage/commands/k3d_cluster_create/

| 옵션 | 뜻 | 기본값 |
| --- | --- | --- |
| `-s, --servers N` | server 노드 수 | 1 |
| `-a, --agents N` | agent 노드 수 | 0 |
| `-i, --image` | k3s 이미지. 버전 고정용 | k3d 릴리스 시점 기본 k3s |
| `--api-port [HOST:]PORT` | API를 호스트 어느 포트로 낼지. `127.0.0.1:61118`이면 로컬 전용 | 임의 포트 |
| `-p HOST:CONTAINER@NODE` | 노드 포트를 호스트로 매핑. `8081:80@loadbalancer`가 Ingress 진입 | 없음 |
| `--k3s-arg "ARG@NODE"` | k3s 프로세스에 인자 전달. `"--disable=traefik@server:0"` | 없음 |
| `-v SRC:DEST@NODE` | 호스트 디렉터리를 노드에 마운트 | 없음 |
| `--servers-memory`, `--agents-memory` | 노드 컨테이너 메모리 상한 | 제한 없음 |
| `--registry-create NAME` | k3d 관리 로컬 레지스트리 생성·연결 | 없음 |
| `-c, --config FILE` | 위 옵션 전부를 YAML 파일로 | |

`@NODEFILTER` 표기: `@server:0`, `@agent:0,1`, `@loadbalancer`, `@all` — 어느 노드에 적용할지.

## 관련 노트

- [[구성도]] — server/agent 역할, 규모별 구성, 실서버 3대를 k3d로 흉내 내기
- [[클러스터]] — lab(server 1 + agent 2), lab3(server 3) 생성 명령·설정 파일·확인·장애 리허설
