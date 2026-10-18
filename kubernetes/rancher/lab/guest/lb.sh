#!/usr/bin/env bash
# [lb, root] 04-lb-haproxy.sh 가 표준입력으로 넘겨 실행한다. /tmp/haproxy.cfg 를 적용한다.
set -euo pipefail

rpm -q haproxy >/dev/null 2>&1 || dnf install -y -q haproxy
# 최초 1회만 원본 백업
[ -e /etc/haproxy/haproxy.cfg.orig ] || cp /etc/haproxy/haproxy.cfg /etc/haproxy/haproxy.cfg.orig

haproxy -c -q -f /tmp/haproxy.cfg || { echo "haproxy.cfg 문법 오류"; exit 1; }
install -m 644 /tmp/haproxy.cfg /etc/haproxy/haproxy.cfg
# SELinux 가 HAProxy 의 9345, 6443 연결을 막지 않도록 허용
setsebool -P haproxy_connect_any 1
systemctl enable haproxy >/dev/null 2>&1
systemctl restart haproxy

# 80, 443, 6443, 9345 가 보여야 함. RKE2·Rancher 설치 전에는 뒤쪽 서버가 모두 DOWN 이 정상
ss -lntp | grep haproxy
