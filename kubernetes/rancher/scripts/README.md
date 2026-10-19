# RKE2 MGMT 설치 스크립트

[2. 설치](../2.%20설치.md)의 4.3 반입 경로를 스크립트로 묶은 것이다. 세 서버가 같은 스크립트를 쓰고, 노드 번호(1·2·3)로 서버별 동작이 갈린다. Rancher 설치(7~10단계)는 포함하지 않는다.

| 파일 | 하는 일 | 서버 변경 |
|---|---|---|
| `cluster.env.example` | 값 템플릿. `cluster.env`로 복사해 채운다 | - |
| `00-check-network.sh` | 외부 HTTPS·DNS·VIP·MGMT 간 포트·Nexus·시간 동기화 확인 | 없음 (읽기 전용) |
| `01-prepare.sh` | firewalld·NetworkManager·nm-cloud-setup·swap·Docker·외부 저장소·container-selinux·bind mount 처리 후 확인 | 있음 |
| `02-install.sh` | 반입 파일 검증, rke2-selinux, 이미지 묶음, RKE2 tar 설치, 토큰, config, Traefik(1번만), 기동, Ready 대기, 클러스터 확인 | 있음 |

세 스크립트 모두 여러 번 실행해도 된다. 이미 된 작업은 건너뛰고 확인만 한다. 이미 RKE2가 떠 있는 노드에서 `02-install.sh`를 실행하면 설치 없이 config 검증과 상태 확인만 한다.

## 준비

PC에서 받은 반입 묶음(4.3)과 이 `scripts` 폴더를 각 서버 홈으로 옮긴다.

```bash
# 각 서버에서
cd ~/scripts
cp cluster.env.example cluster.env
vi cluster.env          # 도메인·VIP·MGMT IP·조인 주소 입력. 세 서버 모두 같은 값
```

## 서버별 실행 순서

| 순서 | 서버 | 명령 | 확인 |
|---|---|---|---|
| 1 | 3대 모두 | `sudo bash 00-check-network.sh <번호>` | FAIL이 없어야 한다. 4.1 경로 주소의 WARN은 4.3이면 무시 |
| 2 | 3대 모두 | `sudo bash 01-prepare.sh <번호>` | 종료 시 `[재부팅 필요]`가 나오면 `sudo reboot` 후 다시 실행 |
| 3 | MGMT-1 | `sudo bash 02-install.sh 1` | `mgmt-1 Ready`, etcd 1개 |
| 4 | MGMT-1 | 토큰 전송 (아래) | |
| 5 | MGMT-2 | `sudo bash 02-install.sh 2` | `mgmt-2 Ready`, etcd 2개. 확인 질문에 `y` |
| 6 | MGMT-3 | `sudo bash 02-install.sh 3` | 바로 이어서. 3대 Ready, etcd 3개, Traefik 3/3 |

`01-prepare.sh`의 종료 코드: 0 정상, 1 FAIL 있음, 2 재부팅 필요.

토큰 전송은 MGMT-1에서 한다. 토큰을 화면이나 채팅에 출력하지 않는다.

```bash
# MGMT-1
sudo install -m 600 -o "$USER" /var/lib/rancher/rke2/server/token /tmp/rke2-token
scp /tmp/rke2-token <계정>@<MGMT-2 IP>:/tmp/rke2-token && rm -f /tmp/rke2-token
```

`02-install.sh`가 MGMT-2·3의 `/tmp/rke2-token`을 `/etc/rancher/rke2/server-token`으로 옮기고 임시 파일을 지운다. 토큰이 없으면 이 안내를 출력하고 멈춘다.

## 스크립트가 막아 주는 실수

이번 설치에서 실제로 겪은 문제를 미리 검사한다.

| 실수 | 스크립트 동작 |
|---|---|
| `\|\| exit 1`로 SSH 접속이 끊김 | 스크립트는 별도 프로세스라 실패해도 셸이 끊기지 않는다 |
| 긴 명령·YAML을 붙여 넣다 줄바꿈·들여쓰기가 깨짐 | config와 Traefik 설정을 스크립트가 직접 쓴다 |
| MGMT-1 config를 복사해 `node-name`·`node-ip`가 빠짐 → hostname으로 조인 | 기동 전에 `node-name`·`node-ip`·`server`·`tls-san`을 검증하고 틀리면 멈춘다 |
| config에 토큰 값을 주석으로 남김 | `token:` 줄을 지우고 경고한다 |
| Docker를 끄고 재부팅하지 않음 → FORWARD DROP | `docker0`·DOCKER 체인이 남아 있으면 설치를 거부한다 |
| EPEL 등 막힌 저장소로 dnf 실패 | `DISABLE_REPOS`를 끈다 |
| Windows에서 받은 `install.sh`의 CRLF | 실행 전에 정리한다 |
| `sudo rke2`가 `command not found` | `/usr/local/bin/rke2` 전체 경로를 쓴다 |
| MGMT-3를 MGMT-2 확인 전에 기동 | 2·3번은 기동 전에 앞 노드 Ready 확인을 묻는다 |

## 하지 않는 것

- PC에서 반입 파일 받기 (문서 4.3 PowerShell 블록)
- MGMT-1 → MGMT-2·3 토큰 전송
- 재부팅 (필요하다고 알려 주기만 한다)
- Helm·Rancher 설치, 인증서, L4 설정
- 이미 조인한 노드의 이름 변경 (문서 6단계 아래 절차)
