#!/usr/bin/env bash
# PC1 전용. Isaac Sim + nav2 + JPEG republish 를 한 번에 띄운다.
# Ctrl-C 로 전부 정리된다.
# usage: ./publisher.sh
#        RGB_TOPIC=/my/cam/image_raw ./publisher.sh
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ISAAC_ROOT=${ISAAC_ROOT:-$HOME/dev_ws/isaac_sim/isaacsim/_build/linux-x86_64/release}
LIDAR_TOPIC=${LIDAR_TOPIC:-/front_3d_lidar/lidar_points}

[[ -x $ISAAC_ROOT/python.sh ]] || { echo "no python.sh at $ISAAC_ROOT — set ISAAC_ROOT" >&2; exit 1; }

source /opt/ros/humble/setup.bash
[[ -f $HERE/install/setup.bash ]] || { echo "run 'colcon build' first" >&2; exit 1; }
source "$HERE/install/setup.bash"

trap 'kill 0' EXIT

echo "== Isaac Sim"
"$ISAAC_ROOT/python.sh" "$HERE/isaac/nova_carter_ros.py" &

echo "== waiting for $LIDAR_TOPIC (max ${LIDAR_WAIT:-300}s)"
deadline=$((SECONDS + ${LIDAR_WAIT:-300}))
until ros2 topic list 2>/dev/null | grep -qx "$LIDAR_TOPIC"; do
  if (( SECONDS > deadline )); then
    echo "timeout — '$LIDAR_TOPIC' 이 없다. 현재 토픽:" >&2
    ros2 topic list >&2
    echo "'/carter1/...' 처럼 네임스페이스가 붙어 있으면 tools/strip_robot_namespace.py 를 돌려라" >&2
    exit 1
  fi
  sleep 3
done

# 카메라 토픽 이름은 씬 버전에 따라 다르다 — 없으면 RGB_TOPIC 으로 직접 지정
RGB_TOPIC=${RGB_TOPIC:-$(ros2 topic list | grep -m1 'image_raw$' || true)}
[[ -n $RGB_TOPIC ]] || { echo "no *image_raw topic found — set RGB_TOPIC" >&2; exit 1; }
echo "== rgb source: $RGB_TOPIC -> /net_test/rgb/compressed"

ros2 run image_transport republish raw compressed \
  --ros-args -r in:="$RGB_TOPIC" -r out:=/net_test/rgb &

echo "== nav2"
ros2 launch carter_navigation carter_navigation.launch.py &

wait
