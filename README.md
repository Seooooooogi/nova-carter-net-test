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
ros2 topic list | grep -E 'cmd_vel|lidar_points|odom|tf'
ros2 topic info /cmd_vel --verbose
```

`/carter1/...` 로 나오면 씬 네임스페이스를 벗겨야 nav2 가 로봇을 움직인다.

```bash
R=$HOME/dev_ws/isaac_sim/isaacsim/_build/linux-x86_64/release
EXT=$R/extscache/$(ls $R/extscache | grep -m1 omni.usd.libs)
PYTHONPATH=$EXT LD_LIBRARY_PATH=$EXT/bin:$R/kit:$R/kit/kernel/plugins \
  $R/kit/python/bin/python3 tools/strip_robot_namespace.py isaac/scenes/carter_warehouse_navigation.usd
```

## 2. PC1~5 — 측정

```bash
./probe.sh
DURATION=60 ./probe.sh
TOPICS="/scan" ./probe.sh
./probe.sh --selftest
```

## 3. PC2~5 — 영상 확인

```bash
ros2 run rqt_image_view rqt_image_view /front_stereo_camera/left/image_raw/compressed
```

## 4. PC1 — nav2 주행 확인

```bash
source install/setup.bash
ros2 run commander nav_to_pose
```

## 합격 기준

| 항목 | 기준 |
|------|------|
| 수신 Hz | PC1 로컬 baseline 대비 90% 이상 |
| 대역폭 | 기록만 (스위치 포화 판단) |
| nav2 주행 | 목표 pose 도달 성공 |

## 주의

- 첫 실행은 인터넷 필요 — USD 씬이 로봇/창고 에셋을 NVIDIA S3 에서 원격 참조한다. 무선 AP 로 받고, 이후 `~/.cache/ov` 에 캐시된다.
- `./setup.sh` 는 유선 gateway 를 비운다. 기본 경로가 무선으로 유지되어야 인터넷이 살아 있다.
- PC2~5 에서 raw 토픽 `/front_stereo_camera/left/image_raw` 를 구독하지 말 것 — DDS 는 구독자가 붙는 순간부터 전송한다. 1080p30 raw 는 약 180 MB/s 라 2.5G 스위치를 혼자 포화시킨다. rqt_image_view 드롭다운에서 반드시 `/compressed` 가 붙은 쪽을 고른다.
- 배포된 씬은 로봇 ROS 그래프에 `carter1` 네임스페이스가 박혀 있어 `/carter1/cmd_vel`, `/carter1/tf` 로 나간다. nav2 params 는 네임스페이스 없는 토픽을 쓰므로 그대로 두면 목표를 줘도 로봇이 안 움직인다. 이 저장소의 USD 는 이미 벗겨 둔 상태다 (`tools/strip_robot_namespace.py`).
- 카메라 토픽 이름이 다르면 `RGB_TOPIC=/your/topic ./publisher.sh`.
- Isaac Sim 경로가 다르면 `ISAAC_ROOT=/path/to/release ./publisher.sh`.

설계 문서: [docs/superpowers/specs/2026-08-14-nova-carter-net-test-design.md](docs/superpowers/specs/2026-08-14-nova-carter-net-test-design.md)
