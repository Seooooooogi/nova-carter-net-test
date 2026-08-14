"""front_hawk 그래프의 끊긴 연결을 되살려 RGB 카메라를 발행시킨다.

배포된 씬은 /World/Nova_Carter_ROS_1/front_hawk 하위 노드들의 입력 연결을 USD
list-op 의 "deleted" 항목으로 끊어 두었다. 그 결과 on_playback_tick 은 뛰지만
하위 노드가 한 번도 평가되지 않아 /front_stereo_camera/left/image_raw 도,
/front_stereo_imu/imu 도 나오지 않는다.

이 스크립트는 그 deleted 항목만 비운다. 연결 자체는 payload(Nova_Carter_ROS.usd)에
그대로 있으므로, 삭제 지시만 걷어내면 원래 연결이 되살아난다.

여러 번 실행해도 결과가 같다.

usage:
  ./tools/isaac_python.sh tools/enable_front_camera.py isaac/scenes/carter_warehouse_navigation.usd
"""

import sys

from pxr import Sdf

GRAPH_SUFFIX = "front_hawk"


def find_graph_specs(layer):
    found = []

    def walk(spec):
        for child in spec.nameChildren:
            if child.name == GRAPH_SUFFIX:
                found.append(child)
            walk(child)

    walk(layer.pseudoRoot)
    return found


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

        graphs = find_graph_specs(layer)
        if not graphs:
            print(f"{path}: no '{GRAPH_SUFFIX}' graph in this layer — nothing to do")
            continue

        restored = 0
        for graph in graphs:
            for node in graph.nameChildren:
                for attr in node.attributes:
                    deleted = list(attr.connectionPathList.deletedItems)
                    if not deleted:
                        continue
                    attr.connectionPathList.deletedItems = []
                    restored += 1
                    for d in deleted:
                        print(f"{path}: restore {node.name}.{attr.name} <- {d}")

        if restored:
            layer.Save()
            changed_any = True
            print(f"{path}: restored {restored} connection(s)")
        else:
            print(f"{path}: already restored")

    print("changed" if changed_any else "no change")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
