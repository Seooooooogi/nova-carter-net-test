"""USD 씬의 로봇 ROS 2 그래프 네임스페이스를 비운다.

배포된 씬은 로봇 그래프에 node_namespace='carter1' 이 박혀 있어 토픽이
/carter1/cmd_vel, /carter1/front_3d_lidar/lidar_points, /carter1/tf 로 나간다.
반면 carter_navigation_params.yaml 과 carter_navigation.launch.py 는 네임스페이스
없는 토픽을 쓴다 — 이 불일치 때문에 nav2 가 로봇을 움직이지 못한다.

여러 번 실행해도 결과가 같다.

usage:
  ./tools/isaac_python.sh tools/strip_robot_namespace.py isaac/scenes/carter_warehouse_navigation.usd
"""

import sys

from pxr import Sdf


def collect(spec, out):
    for child in spec.nameChildren:
        if child.name == "node_namespace":
            for attr in child.attributes:
                if attr.name == "inputs:value":
                    out.append(attr)
        collect(child, out)


def main(paths):
    if not paths:
        print(__doc__)
        return 2

    changed_any = False
    for path in paths:
        layer = Sdf.Layer.FindOrOpen(path)
        if layer is None:
            print(f"cannot open: {path}", file=sys.stderr)
            return 1

        attrs = []
        collect(layer.pseudoRoot, attrs)
        if not attrs:
            print(f"{path}: no node_namespace found — nothing to do")
            continue

        changed = 0
        for attr in attrs:
            before = attr.default
            if before in ("", None):
                continue
            attr.default = ""
            changed += 1
            print(f"{path}: {attr.path} '{before}' -> ''")

        if changed:
            layer.Save()
            changed_any = True
        else:
            print(f"{path}: already stripped ({len(attrs)} node_namespace, all empty)")

    print("changed" if changed_any else "no change")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
