#!/usr/bin/env bash
# PC1 전용. Isaac Sim + nav2 + JPEG republish 를 한 번에 띄운다.
# Ctrl-C 로 전부 정리된다.
# usage: ./publisher.sh
#        RGB_TOPIC=/my/cam/image_raw ./publisher.sh
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
LIDAR_TOPIC=${LIDAR_TOPIC:-/front_3d_lidar/lidar_points}

# 설치 형태마다 경로가 달라서 탐색에 맡긴다. ISAAC_ROOT 로 덮어쓸 수 있다.
ISAAC_ROOT=$("$HERE/tools/isaac_python.sh" --root)
echo "== Isaac Sim: $ISAAC_ROOT ($(cat "$ISAAC_ROOT/VERSION" 2>/dev/null || echo 'version unknown'))"

DISTRO=${ROS_DISTRO:-}
if [[ -z $DISTRO || ! -d /opt/ros/$DISTRO ]]; then
  for d in jazzy humble; do [[ -d /opt/ros/$d ]] && { DISTRO=$d; break; }; done
fi
[[ -n $DISTRO ]] || { echo "no ROS 2 under /opt/ros — set ROS_DISTRO" >&2; exit 1; }
source "/opt/ros/$DISTRO/setup.bash"
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
echo "== rgb: $RGB_TOPIC -> $RGB_TOPIC/compressed"

# republish 인자 형식이 배포판마다 다르다. Jazzy 의 image_transport 5.x 는
# in_transport/out_transport 를 위치인자로 안 받고 파라미터로 받으며,
# 출력 토픽은 -r out:= 이 안 먹어서 최종 이름인 out/compressed 를 리맵해야 한다.
if [[ $DISTRO == humble ]]; then
  ros2 run image_transport republish raw compressed \
    --ros-args -r in:="$RGB_TOPIC" -r out:="$RGB_TOPIC" &
else
  ros2 run image_transport republish \
    --ros-args -p in_transport:=raw -p out_transport:=compressed \
    -r in:="$RGB_TOPIC" \
    -r out/compressed:="$RGB_TOPIC/compressed" &
fi

echo "== nav2"
ros2 launch carter_navigation carter_navigation.launch.py &

wait
