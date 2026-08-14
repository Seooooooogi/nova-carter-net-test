# nova-carter-net-test 설계

작성일: 2026-08-14

## 1. 목적

MSI 노트북 5대를 2.5G 전용 스위치로 묶은 폐쇄망에서, Isaac Sim nova_carter 씬이
발행하는 **RGB(JPEG 압축) 와 3D LiDAR 토픽이 4대의 원격 구독자에게 원활히
전달되는지** 측정한다. 동시에 ROS 2 트래픽이 천장 AP(무선)로 새지 않고 유선으로만
흐르는지 검증한다.

무선 AP 는 ROS 전송로가 아니라 **인터넷 경로**다 (apt 패키지 설치, Isaac Sim 원격
에셋 다운로드). 유선망은 gateway 를 비워 둔 폐쇄망이므로 인터넷이 없다.

## 2. 시스템 구성

| 노드 | 유선 IP | 역할 |
|------|---------|------|
| PC1 | 10.10.0.1 | Isaac Sim (nova_carter warehouse) + nav2 + JPEG republish + 로컬 baseline 측정 |
| PC2~5 | 10.10.0.2 ~ 10.10.0.5 | 원격 구독자 — `probe.sh` 로 Hz/대역폭 측정, `rqt_image_view` 로 영상 육안 확인 |

공통 환경:

- Ubuntu 22.04 + ROS 2 Humble
- `ROS_DOMAIN_ID=50`
- `RMW_IMPLEMENTATION=rmw_fastrtps_cpp`
- `FASTRTPS_DEFAULT_PROFILES_FILE=$HOME/.ros/fastdds_wired.xml`

FastDDS `interfaceWhiteList` 에 `10.10.0.1` ~ `10.10.0.5` 만 등록한다. 이 목록에
없는 인터페이스(무선 NIC)로는 DDS 가 소켓을 열지 않으므로, 토픽이 AP 로 나가지
않는다.

## 3. 데이터 경로

```
Isaac Sim (PC1)
  ├─ /front_stereo_camera/left/image_raw   (sensor_msgs/Image, raw)
  │     └─ image_transport republish ──▶ /net_test/rgb/compressed   ← 네트워크로 나가는 유일한 영상
  └─ /front_3d_lidar/lidar_points          (sensor_msgs/PointCloud2)
        └─ pointcloud_to_laserscan ──▶ /scan ──▶ nav2 (PC1 로컬)
```

Isaac Sim 의 ROS 2 bridge 는 raw `sensor_msgs/Image` 만 발행한다. JPEG 압축은
`image_transport republish raw compressed` 노드가 PC1 에서 수행한다.

raw 토픽은 원격 구독자가 붙지 않으므로 DDS 가 전송하지 않는다 (DDS 는 매칭된
구독자가 있을 때만 데이터를 보낸다). 따라서 네트워크에는 JPEG 만 흐른다.

카메라 토픽 이름은 씬 버전에 따라 달라질 수 있어 `publisher.sh` 가 런타임에
`ros2 topic list` 로 자동 탐지한다. `RGB_TOPIC` 환경변수로 덮어쓸 수 있다.

## 4. 측정 항목과 합격 기준

| 항목 | 측정 방법 | 합격 기준 |
|------|-----------|-----------|
| 수신 Hz | `ros2 topic hz` 평균 rate | PC1 로컬 baseline 대비 90% 이상 |
| 대역폭 | `ros2 topic bw` MB/s | 기록만 — 스위치 포화 판단 근거 |
| nav2 주행 | `ros2 run commander nav_to_pose` | 목표 pose 도달 성공 |
| 유선 격리 | 무선 NIC 에서 `tcpdump 'udp portrange 7400-7600'` | 10초간 0 패킷 |

손실률은 `1 - (원격 Hz / PC1 로컬 Hz)` 로 계산한다. PC1 에서도 같은 `probe.sh` 를
돌려 baseline 을 만들기 때문에 별도 기준값을 하드코딩하지 않는다.

end-to-end 지연은 측정하지 않는다. 노트북 간 시계 동기화(chrony/PTP)가 없으면
`header.stamp` 기준 지연값이 무의미하기 때문이다.

## 5. 구성 요소

```
nova-carter-net-test/
├── setup.sh                    # 노드 1대 셋업 (인자: 노드 번호 1~5)
├── publisher.sh                # PC1 전체 실행 (Isaac Sim + nav2 + republish)
├── probe.sh                    # 측정 → results/<host>.csv
├── config/fastdds_wired.xml    # interfaceWhiteList 10.10.0.1~5
├── isaac/nova_carter_ros.py    # 씬 로드 + 자동 Play
├── isaac/scenes/carter_warehouse_navigation.usd
└── src/{carter_navigation,commander}/
```

### setup.sh

멱등(idempotent)하게 동작한다 — 여러 번 실행해도 결과가 같다.

1. `ros-humble-compressed-image-transport` 설치 (무선 인터넷 필요)
2. `nmcli` 로 유선 연결에 `10.10.0.<N>/24` 고정, gateway/DNS 비움
   - gateway 를 비워야 기본 경로가 무선으로 유지되어 인터넷이 살아 있다
3. `config/fastdds_wired.xml` → `~/.ros/` 복사
4. `~/.bashrc` 에 환경변수 3종 추가 (마커 주석으로 중복 방지)
5. `ros2 daemon` 재시작

### publisher.sh

Isaac Sim → 토픽 대기 → nav2 launch → republish 를 순서대로 띄우고, 종료 시
프로세스 그룹을 정리한다. README 에 같은 내용을 터미널 3개로 나눠 실행하는
개별 명령어도 함께 적는다.

### probe.sh

대상 토픽마다 `ros2 topic hz` / `ros2 topic bw` 를 정해진 시간 동안 돌린 뒤 마지막
출력 줄을 파싱해 CSV 한 줄로 append 한다. 대역폭 단위(B/s, KB/s, MB/s)는 MB/s 로
정규화한다.

파싱 로직은 `--selftest` 로 검증한다. 샘플 출력 문자열을 파서에 넣어 기대값과
비교하며, 실패 시 exit code 1 을 낸다.

CSV 스키마: `timestamp,host,topic,hz,mb_per_s`

## 6. 제약과 전제

- **첫 실행 시 인터넷 필요.** `carter_warehouse_navigation.usd` 는 로봇 본체
  (`Nova_Carter_ROS.usd`)와 창고 에셋을 NVIDIA S3 에서 원격 참조한다. 유선 폐쇄망만
  연결된 상태에서는 씬이 열리지 않는다. 첫 실행 후에는 `~/.cache/ov` 에 캐시된다.
- **USD 씬은 NVIDIA 저작물**이다. repo 에 포함하되 NOTICE 에 출처를 명시한다.
- **씬의 로봇 ROS 그래프에 `carter1` 네임스페이스가 박혀 있었다.** 로컬 USD 레이어가
  `differential_drive` / `ros_lidars` / `transform_tree_odometry` / `chassis_imu` 네 그래프의
  `node_namespace.inputs:value` 를 `'carter1'` 로 override 한다 (세 씬 파일 모두 동일,
  multi 씬은 `carter1` + `carter2`). 그 결과 실제 토픽이 `/carter1/cmd_vel`,
  `/carter1/front_3d_lidar/lidar_points`, `/carter1/chassis/odom`, `/carter1/tf` 가 되는데,
  `carter_navigation_params.yaml` 은 `/chassis/odom` · `scan` 을, launch 의
  `pointcloud_to_laserscan` 은 `/front_3d_lidar/lidar_points` 를 네임스페이스 없이 쓴다.
  이 불일치를 두면 nav2 가 목표를 받아도 `/cmd_vel` 구독자가 없어 로봇이 움직이지 않는다.
  `tools/strip_robot_namespace.py` 로 네 값을 빈 문자열로 만들어 단일 로봇 구성에 맞춘다.
  카메라 그래프(`front_hawk`)는 override 대상이 아니라 토픽 이름이 그대로다.
- Isaac Sim 설치 경로는 `ISAAC_ROOT` 환경변수로 덮어쓸 수 있다. 기본값은
  `$HOME/dev_ws/isaac_sim/isaacsim/_build/linux-x86_64/release`.
- FastDDS `interfaceWhiteList` 는 IP 주소만 받는다 (Humble 의 FastDDS 2.6 기준).
  인터페이스 이름 지정은 불가하므로 고정 IP 가 전제 조건이다.

## 7. 범위 밖

- 무선(AP)을 ROS 전송로로 쓰는 비교 측정 — 유선 전용 구성만 검증한다
- end-to-end 지연 측정 — 시계 동기화 인프라가 없다
- SSH 오케스트레이션 — 각 노트북에서 수동 실행한다
- 다중 로봇(multi-carter) 시나리오
