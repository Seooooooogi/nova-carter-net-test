#!/usr/bin/env bash
# 노트북 1대를 유선 폐쇄망 노드로 셋업한다. 여러 번 실행해도 결과가 같다.
# usage: ./setup.sh <node-number 1..5>
set -euo pipefail

N=${1:-}
[[ $N =~ ^[1-5]$ ]] || { echo "usage: $0 <node-number 1..5>" >&2; exit 2; }

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
DOMAIN=${ROS_DOMAIN_ID:-50}

# 1) JPEG 압축 플러그인 — 인터넷(무선 AP) 필요
if ! dpkg -s ros-humble-compressed-image-transport >/dev/null 2>&1; then
  echo "== installing ros-humble-compressed-image-transport (needs internet via Wi-Fi)"
  sudo apt-get update
  sudo apt-get install -y ros-humble-compressed-image-transport
fi

# 2) 유선 고정 IP. gateway 를 비워야 기본 경로가 무선으로 남아 인터넷이 살아 있다.
CON=$(nmcli -t -f NAME,TYPE con show | awk -F: '$2=="802-3-ethernet"{print $1; exit}')
[[ -n $CON ]] || { echo "no wired (802-3-ethernet) connection found" >&2; exit 1; }

echo "== wired connection: $CON -> 10.10.0.$N/24"
nmcli con mod "$CON" ipv4.method manual ipv4.addresses "10.10.0.$N/24" ipv4.gateway "" ipv4.dns ""
nmcli con up "$CON" >/dev/null

# 3) FastDDS 유선 전용 프로파일
mkdir -p "$HOME/.ros"
cp "$HERE/config/fastdds_wired.xml" "$HOME/.ros/"

# 4) 환경변수 — 마커 주석으로 중복 추가를 막는다
if ! grep -q '# nova-carter-net-test' "$HOME/.bashrc"; then
  cat >> "$HOME/.bashrc" <<EOF

# nova-carter-net-test
export ROS_DOMAIN_ID=$DOMAIN
export RMW_IMPLEMENTATION=rmw_fastrtps_cpp
export FASTRTPS_DEFAULT_PROFILES_FILE=\$HOME/.ros/fastdds_wired.xml
EOF
fi

export ROS_DOMAIN_ID=$DOMAIN
export RMW_IMPLEMENTATION=rmw_fastrtps_cpp
export FASTRTPS_DEFAULT_PROFILES_FILE=$HOME/.ros/fastdds_wired.xml
ros2 daemon stop >/dev/null 2>&1 || true
ros2 daemon start >/dev/null 2>&1 || true

echo
echo "== done. node=$N  ip=10.10.0.$N  ROS_DOMAIN_ID=$DOMAIN"
ip -4 addr show dev "$(nmcli -t -f GENERAL.DEVICES con show "$CON" | cut -d: -f2)" | grep inet || true
echo "open a new terminal (or: source ~/.bashrc)"
