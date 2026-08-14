# nova-carter-net-test

Isaac Sim nova_carter + nav2 를 2.5G 전용 스위치 폐쇄망에서 돌려, RGB(JPEG) 와 3D LiDAR 토픽이 원격 노트북 4대에 전달되는지 측정한다.
ROS 2 트래픽은 유선 전용, 무선 AP 는 인터넷 전용.

| 노드 | 유선 IP | 역할 |
|------|---------|------|
| PC1 | 10.10.0.1 | Isaac Sim + nav2 + JPEG republish + baseline 측정 |
| PC2~5 | 10.10.0.2~5 | 측정 + 영상 확인 |

## 0. 준비 — 5대 공통

```bash
git clone https://github.com/Seooooooogi/nova-carter-net-test.git
cd nova-carter-net-test
./setup.sh 1          # 노트북마다 1~5 중 자기 번호
source ~/.bashrc
colcon build --symlink-install
```

## 1. PC1 — 전체 실행

```bash
./publisher.sh
```

## 1-a. PC1 — 개별 실행 (터미널 3개)

```bash
# 터미널 1 — Isaac Sim
$HOME/dev_ws/isaac_sim/isaacsim/_build/linux-x86_64/release/python.sh isaac/nova_carter_ros.py
```

```bash
# 터미널 2 — JPEG republish
source install/setup.bash
ros2 run image_transport republish raw compressed \
  --ros-args -r in:=/front_stereo_camera/left/image_raw \
             -r out:=/front_stereo_camera/left/image_raw
```

```bash
# 터미널 3 — nav2
source install/setup.bash
ros2 launch carter_navigation carter_navigation.launch.py
```

## 1-b. PC1 — 토픽 이름 확인 (첫 실행 시 1회)

```bash
ros2 topic list | grep -E 'cmd_vel|lidar_points|image_raw|tf'
```

기대값: `/cmd_vel` `/front_3d_lidar/lidar_points` `/front_stereo_camera/left/image_raw` `/tf`

`/carter1/...` 로 나오거나 `image_raw` 가 없으면 씬을 고친다 (저장소의 USD 는 이미 적용된 상태).

```bash
R=$HOME/dev_ws/isaac_sim/isaacsim/_build/linux-x86_64/release
EXT=$R/extscache/$(ls $R/extscache | grep -m1 omni.usd.libs)
export PYTHONPATH=$EXT LD_LIBRARY_PATH=$EXT/bin:$R/kit:$R/kit/kernel/plugins
S=isaac/scenes/carter_warehouse_navigation.usd
$R/kit/python/bin/python3 tools/strip_robot_namespace.py "$S"
$R/kit/python/bin/python3 tools/enable_front_camera.py "$S"
```

## 2. PC2~5 — 영상 확인

```bash
ros2 run rqt_image_view rqt_image_view /front_stereo_camera/left/image_raw/compressed
```

## 3. PC1 — nav2 주행 확인

```bash
source install/setup.bash
ros2 run commander nav_to_pose
```

설계 문서: [docs/superpowers/specs/2026-08-14-nova-carter-net-test-design.md](docs/superpowers/specs/2026-08-14-nova-carter-net-test-design.md)
