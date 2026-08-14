#!/usr/bin/env bash
# 토픽별 수신 Hz / 대역폭을 측정해 results/<host>.csv 에 append 한다.
# usage: ./probe.sh            (기본 20초씩)
#        DURATION=60 ./probe.sh
#        TOPICS="/scan" ./probe.sh
#        ./probe.sh --selftest (파서 자체 검증)
set -euo pipefail

DURATION=${DURATION:-20}
TOPICS=${TOPICS:-"/net_test/rgb/compressed /front_3d_lidar/lidar_points /scan"}

parse_hz() { grep -oE 'average rate: [0-9.]+' | tail -1 | awk '{print $3}'; }

# ros2 topic bw 는 B/s, KB/s, MB/s 중 하나로 출력한다 — MB/s 로 정규화
parse_bw() {
  grep -oE '[0-9.]+ [KM]?B/s from' | tail -1 | awk '{
    v = $1; u = $2
    if (u == "KB/s") v /= 1024
    else if (u == "B/s") v /= 1048576
    printf "%.4f", v
  }'
}

if [[ ${1:-} == --selftest ]]; then
  fail=0
  check() { [[ $2 == "$3" ]] || { echo "FAIL $1: got '$2' want '$3'"; fail=1; }; }

  check hz "$(printf 'average rate: 29.986\n\tmin: 0.031s\naverage rate: 30.012\n\tmin: 0.030s\n' | parse_hz)" "30.012"
  check bw_mb "$(printf 'Subscribed to [/x]\n1.02 MB/s from 30 messages\n' | parse_bw)" "1.0200"
  check bw_kb "$(printf '512.00 KB/s from 30 messages\n' | parse_bw)" "0.5000"
  check bw_b  "$(printf '1048576.0 B/s from 30 messages\n' | parse_bw)" "1.0000"
  check hz_empty "$(printf 'no messages\n' | parse_hz)" ""

  [[ $fail -eq 0 ]] && echo "selftest OK"
  exit $fail
fi

[[ -n ${ROS_DISTRO:-} ]] || source /opt/ros/humble/setup.bash

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
mkdir -p "$HERE/results"
OUT="$HERE/results/$(hostname).csv"
[[ -f $OUT ]] || echo "timestamp,host,topic,hz,mb_per_s" > "$OUT"

echo "ROS_DOMAIN_ID=${ROS_DOMAIN_ID:-unset}  profile=${FASTRTPS_DEFAULT_PROFILES_FILE:-unset}"
echo "output: $OUT"

for t in $TOPICS; do
  echo "== $t  (${DURATION}s hz, ${DURATION}s bw)"
  # SIGINT 로 끊어야 ros2 cli 가 버퍼를 flush 하고 마지막 줄을 남긴다
  hz=$(PYTHONUNBUFFERED=1 timeout -s INT "$DURATION" ros2 topic hz "$t" 2>/dev/null | parse_hz || true)
  bw=$(PYTHONUNBUFFERED=1 timeout -s INT "$DURATION" ros2 topic bw "$t" 2>/dev/null | parse_bw || true)
  # 측정 실패는 NA 로 남긴다 — 값을 지어내지 않는다
  echo "$(date -Is),$(hostname),$t,${hz:-NA},${bw:-NA}" | tee -a "$OUT"
done

echo
column -s, -t "$OUT"
