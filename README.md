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
  --ros-args -r in:=/front_stereo_camera/left/image_raw -r out:=/net_test/rgb
```

```bash
# 터미널 3 — nav2
source install/setup.bash
ros2 launch carter_navigation carter_navigation.launch.py
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
ros2 run rqt_image_view rqt_image_view /net_test/rgb/compressed
```

## 4. 유선 격리 확인 — 무선 NIC 에 DDS 패킷 0

```bash
WIFI=$(nmcli -t -f DEVICE,TYPE dev | awk -F: '$2=="wifi"{print $1; exit}')
sudo timeout 10 tcpdump -ni "$WIFI" 'udp portrange 7400-7600'
```

## 5. PC1 — nav2 주행 확인

```bash
source install/setup.bash
ros2 run commander nav_to_pose
```

## 6. 결과 취합 — PC1

```bash
# sshd 가 없으면 USB 로 results/*.csv 복사
scp rokey@10.10.0.2:~/nova-carter-net-test/results/*.csv results/
column -s, -t results/*.csv
```

## 합격 기준

| 항목 | 기준 |
|------|------|
| 수신 Hz | PC1 로컬 baseline 대비 90% 이상 |
| 대역폭 | 기록만 (스위치 포화 판단) |
| nav2 주행 | 목표 pose 도달 성공 |
| 유선 격리 | 무선 NIC 10초간 0 패킷 |

## 주의

- 첫 실행은 인터넷 필요 — USD 씬이 로봇/창고 에셋을 NVIDIA S3 에서 원격 참조한다. 무선 AP 로 받고, 이후 `~/.cache/ov` 에 캐시된다.
- `./setup.sh` 는 유선 gateway 를 비운다. 기본 경로가 무선으로 유지되어야 인터넷이 살아 있다.
- 카메라 토픽 이름이 다르면 `RGB_TOPIC=/your/topic ./publisher.sh`.
- Isaac Sim 경로가 다르면 `ISAAC_ROOT=/path/to/release ./publisher.sh`.

설계 문서: [docs/superpowers/specs/2026-08-14-nova-carter-net-test-design.md](docs/superpowers/specs/2026-08-14-nova-carter-net-test-design.md)
