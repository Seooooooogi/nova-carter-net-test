#!/usr/bin/env bash
# Isaac Sim 설치 위치를 찾아 그 안의 kit python 으로 pxr(USD API) 스크립트를 실행한다.
#
# usage: ./tools/isaac_python.sh tools/strip_robot_namespace.py isaac/scenes/x.usd
#        ./tools/isaac_python.sh --root          # 찾은 설치 경로만 출력
#        ISAAC_ROOT=/path/to/isaacsim ./tools/isaac_python.sh ...
#
# 설치 형태(소스 빌드 / 바이너리 / Omniverse Launcher)마다 경로가 다르고
# extscache 의 omni.usd.libs 버전 문자열도 설치마다 달라서, 둘 다 탐색한다.
set -euo pipefail

CANDIDATES=(
  "$HOME/isaacsim/_build/linux-x86_64/release"
  "$HOME/dev_ws/isaac_sim/isaacsim/_build/linux-x86_64/release"
  /opt/isaacsim
  "$HOME"/.local/share/ov/pkg/isaac-sim-*
)

# ISAAC_ROOT 를 명시했는데 틀렸으면 조용히 다른 설치본으로 넘어가지 않는다.
# 버전이 다른 설치가 공존할 수 있어서, 엉뚱한 쪽으로 붙으면 알아채기 어렵다.
if [[ -n ${ISAAC_ROOT:-} ]]; then
  [[ -x $ISAAC_ROOT/python.sh ]] || { echo "ISAAC_ROOT 에 python.sh 가 없다: $ISAAC_ROOT" >&2; exit 1; }
  R=$ISAAC_ROOT
else
  R=""
  for d in "${CANDIDATES[@]}"; do
    [[ -x $d/python.sh ]] && { R=$d; break; }
  done
fi

if [[ -z $R ]]; then
  echo "Isaac Sim 을 찾지 못했다. ISAAC_ROOT 를 설정하라 (python.sh 가 있는 디렉토리)." >&2
  printf '  탐색한 경로: %s\n' "${CANDIDATES[@]}" >&2
  exit 1
fi

[[ ${1:-} == --root ]] && { echo "$R"; exit 0; }

EXT_NAME=$(ls "$R/extscache" 2>/dev/null | grep -m1 omni.usd.libs || true)
[[ -n $EXT_NAME ]] || { echo "omni.usd.libs 확장이 없다: $R/extscache" >&2; exit 1; }
EXT=$R/extscache/$EXT_NAME

exec env PYTHONPATH="$EXT" \
  LD_LIBRARY_PATH="$EXT/bin:$R/kit:$R/kit/kernel/plugins" \
  "$R/kit/python/bin/python3" "$@"
