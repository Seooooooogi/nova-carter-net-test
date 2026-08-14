# nova-carter-net-test 설계

작성일: 2026-08-14

## 1. 목적

MSI 노트북 5대를 2.5G 전용 스위치로 묶은 폐쇄망에서, Isaac Sim nova_carter 씬이
발행하는 **RGB(JPEG 압축) 와 3D LiDAR 토픽이 4대의 원격 구독자에게 원활히
전달되는지** 측정한다. ROS 2 트래픽은 FastDDS 설정으로 유선에만 묶는다.

무선 AP 는 ROS 전송로가 아니라 **인터넷 경로**다 (apt 패키지 설치, Isaac Sim 원격
에셋 다운로드). 유선망은 gateway 를 비워 둔 폐쇄망이므로 인터넷이 없다.

## 2. 시스템 구성

| 노드 | 유선 IP | 역할 |
|------|---------|------|
| PC1 | 10.10.0.1 | Isaac Sim (nova_carter warehouse) + nav2 + JPEG republish + 로컬 baseline 측정 |
| PC2~5 | 10.10.0.2 ~ 10.10.0.5 | 원격 구독자 — `ros2 topic hz`/`bw` 로 수동 측정, `rqt_image_view` 로 영상 육안 확인 |

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
  │     └─ image_transport republish
  │           ──▶ /front_stereo_camera/left/image_raw/compressed   ← 네트워크로 나가는 유일한 영상
  └─ /front_3d_lidar/lidar_points          (sensor_msgs/PointCloud2)
        └─ pointcloud_to_laserscan ──▶ /scan ──▶ nav2 (PC1 로컬)
```

Isaac Sim 의 ROS 2 bridge 는 raw `sensor_msgs/Image` 만 발행한다. JPEG 압축은
`image_transport republish raw compressed` 노드가 PC1 에서 수행한다.

raw 토픽은 원격 구독자가 붙지 않으므로 DDS 가 전송하지 않는다 (DDS 는 매칭된
구독자가 있을 때만 데이터를 보낸다). 따라서 네트워크에는 JPEG 만 흐른다.

압축본 토픽은 별도 prefix 를 붙이지 않고 raw 토픽 뒤에 `/compressed` 를 붙인다.
이것이 image_transport 의 표준 규약이라, 구독자가 base 토픽 + `compressed` transport
조합으로 그대로 받을 수 있다.

카메라 토픽 이름의 근거는 씬 payload(`Nova_Carter_ROS.usd`)의 OmniGraph 다:
`front_hawk/camera_namespace.inputs:value = '/front_stereo_camera'` 가
`left_camera_publish_image.inputs:nodeNamespace` 에 연결돼 있고, 같은 노드의
`inputs:topicName = 'left/image_raw'` 다 → `/front_stereo_camera/left/image_raw`.
카메라 그래프는 로봇 레벨 `node_namespace` 를 쓰지 않아 `carter1` 문제와 무관하다.

씬 버전이 바뀔 경우를 대비해 `publisher.sh` 는 런타임에 `ros2 topic list` 로도
탐지하며, `RGB_TOPIC` 환경변수로 덮어쓸 수 있다.

## 4. 측정 항목과 합격 기준

| 항목 | 측정 방법 | 합격 기준 |
|------|-----------|-----------|
| 수신 Hz | `ros2 topic hz` 평균 rate | PC1 로컬 baseline 대비 90% 이상 |
| 대역폭 | `ros2 topic bw` MB/s | 기록만 — 스위치 포화 판단 근거 |
| nav2 주행 | `ros2 run commander nav_to_pose` | 목표 pose 도달 성공 |

손실률은 `1 - (원격 Hz / PC1 로컬 Hz)` 로 계산한다. PC1 에서도 같은 명령을 돌려
baseline 을 만들기 때문에 별도 기준값을 하드코딩하지 않는다.

측정은 수동으로 한다. 저장소는 기동까지만 책임지고 계측 스크립트는 두지 않는다.
`ros2 topic hz` / `ros2 topic bw` 를 각 노드에서 직접 실행한다.

측정 시 주의: `setsid` 나 `timeout -s INT` 로 감싸면 `ros2 topic hz` 가 출력을 한 줄도
남기지 않는다. 평범한 `timeout <초> ros2 topic hz <토픽>` 을 쓴다.

### PC1 로컬 실측 (2026-08-15, RTX 4090, 헤드리스)

| 토픽 | Hz | 대역폭 |
|------|-----|--------|
| `/front_stereo_camera/left/image_raw` | 20.6 | 164 MB/s |
| `/front_3d_lidar/lidar_points` | 41.0 | 3.57 MB/s |
| `/chassis/odom` | 43.4 | — |
| `/tf` | 158.1 | — |
| `/clock` | 43.4 | — |

### Jazzy 실측 (2026-08-15, Ubuntu 24.04 컨테이너 ← 호스트 Isaac Sim 5.1)

Isaac Sim 을 `ROS_DISTRO=jazzy` + 내장 `exts/isaacsim.ros2.bridge/jazzy/lib` 로 띄워
노트북 조합(Isaac Sim 5.1 + Jazzy)을 재현하고, Ubuntu 24.04 + Jazzy 컨테이너에서 측정했다.

| 토픽 | Hz | 대역폭 |
|------|-----|--------|
| `/front_stereo_camera/left/image_raw` (raw) | 35.7 | **251.06 MB/s** (≈2.0 Gbps) |
| `.../image_raw/compressed` (JPEG) | 35.6 | **20.19 MB/s** (≈161 Mbps), 프레임 0.56 MB |
| `/front_3d_lidar/lidar_points` | 40.1 | 3.6 MB/s |
| `/clock`, `/chassis/odom` | 40.2 | — |

JPEG 는 raw 대비 **약 12.5배** 작다. 구독자 4대 기준 JPEG 80 MB/s + LiDAR 14 MB/s ≈
755 Mbps 로 2.5G 스위치에 여유가 있다. raw 였다면 4대에 8 Gbps 라 불가능하다.
그래서 원격 노드는 반드시 `/compressed` 만 구독해야 한다.

end-to-end 지연은 측정하지 않는다. 노트북 간 시계 동기화(chrony/PTP)가 없으면
`header.stamp` 기준 지연값이 무의미하기 때문이다.

## 5. 구성 요소

```
nova-carter-net-test/
├── setup.sh                    # 노드 1대 셋업 (인자: 노드 번호 1~5)
├── publisher.sh                # PC1 전체 실행 (Isaac Sim + nav2 + republish)
├── config/fastdds_wired.xml    # interfaceWhiteList 10.10.0.1~5
├── tools/strip_robot_namespace.py
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

### tools/strip_robot_namespace.py

씬의 로봇 ROS 그래프 네임스페이스(`carter1`)를 빈 문자열로 만든다. 멱등하다.
자세한 배경은 6절 참조.

### tools/enable_front_camera.py

`front_hawk` 그래프의 끊긴 입력 연결을 되살린다. 멱등하다. 자세한 배경은 6절 참조.

## 5-1. ROS 2 Jazzy 관련 확인 사항

검증 PC 5대는 Ubuntu 24.04 + ROS 2 Jazzy + Isaac Sim 5.1 이다. 2026-08-15 에
Ubuntu 24.04 + Jazzy 컨테이너로 실측한 결과:

- **Isaac Sim 의 ROS 백엔드 선택** — `setup_ros_env.sh` 가 `ROS_DISTRO` 가 비어 있을
  때만 내장 라이브러리 경로를 `LD_LIBRARY_PATH` 에 붙인다. 즉 ROS 를 소싱하면 시스템
  ROS 를 쓴다. `python.sh` 는 `setup_ros_env.sh` 를 소싱하지 않는다 (`isaac-sim.sh` 만
  한다). `publisher.sh` 가 ROS 를 먼저 소싱하는 지금 순서가 맞다.
- **Isaac Sim 5.1 ↔ Jazzy 통신 가능** — Isaac 을 내장 jazzy 백엔드로 띄우고 Jazzy 쪽에서
  40 Hz 로 수신 확인.
- **`FASTRTPS_DEFAULT_PROFILES_FILE` 이 맞다** — 같은 XML 을 `FASTDDS_DEFAULT_PROFILES_FILE`
  로 주면 무시된다 (토픽 발견 수가 안 변함). `interfaceWhiteList` 문법도 Fast DDS 2.14.6
  에서 그대로 동작한다 (프로파일 적용 시 발견 토픽 17 → 5).
- **`republish` 인자 형식이 다르다** — Jazzy 의 image_transport 5.1.8 은 위치인자
  `raw compressed` 중 `out_transport` 를 받지 않고, `-r out:=` 리맵도 무시한다.
  `-p in_transport:=raw -p out_transport:=compressed` 와 최종 이름 리맵
  `-r out/compressed:=<토픽>/compressed` 를 써야 한다. `publisher.sh` 가 배포판으로 분기한다.
- **패키지명** — `ros-jazzy-compressed-image-transport` (4.0.7), `ros-jazzy-nav2-bringup`
  (1.3.12), `ros-jazzy-pointcloud-to-laserscan` (2.0.2) 모두 존재.
- **Isaac 의 Python 은 3.11 고정** — Ubuntu 24.04 의 시스템 Jazzy 는 Python 3.12 라 Isaac 이
  시스템 rclpy 를 못 쓴다. 소싱해도 rclpy 는 내장 jazzy 판(3.11)으로 폴백한다. C 라이브러리는
  소싱된 시스템 Jazzy 를 쓴다. 배포판만 일치하면 정상 조합이다.
  주의: `ROS_DISTRO` 와 `LD_LIBRARY_PATH` 의 배포판이 어긋나면(예: `ROS_DISTRO=jazzy` +
  `/opt/ros/humble/lib`) `undefined symbol` 로 bridge 확장이 스스로 꺼진다.
- **nav2 파라미터** — Humble 판 `carter_navigation_params.yaml` 은 Jazzy 에서 못 쓴다
  (`bt_navigator` 가 `plugin_lib_names` 나열 → `navigators` + `nav2_bt_navigator::` 플러그인
  구조로 바뀌고 `docking_server` · `collision_monitor` 가 추가됨). NVIDIA 공식
  `IsaacSim-ros_workspaces/jazzy_ws` 판으로 교체했다.
- 컨테이너 검증 시 주의: `--net=host` 만으로는 Fast DDS 공유메모리 전송이 IPC 네임스페이스를
  넘지 못해 디스커버리만 되고 데이터가 안 온다. `--ipc=host` 를 주거나 UDP 전용 프로파일을
  쓴다. 저장소의 `fastdds_wired.xml` 은 `useBuiltinTransports=false` + UDPv4 라 해당 없음.

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
  2026-08-15 실측으로 확인했다 — 패치 전 `/carter1/cmd_vel`, 패치 후 `/cmd_vel`.
- **씬이 `front_hawk` 그래프 연결을 끊어 두었다.** 로컬 레이어가 USD list-op 의 deleted
  항목으로 `isaac_run_one_simualtion_frame.inputs:execIn`, `isaac_read_imu_node.inputs:execIn`,
  `left_camera_publish_image.inputs:execIn`·`renderProductPath`, `ros2_camera_info_helper.*`
  등 23개 연결을 삭제한다. 그 결과 `on_playback_tick` 은 뛰지만 하위 노드가 한 번도
  평가되지 않아 `/front_stereo_camera/left/image_raw` 도 `/front_stereo_imu/imu` 도 나오지
  않는다 — RGB 측정 자체가 불가능해진다. `tools/enable_front_camera.py` 가 deleted 항목만
  비워 payload 의 원래 연결을 되살린다. 나머지 hawk 3개는 렌더 프로덕트가 `enabled=False`
  라 애초에 영상을 내지 않는다.
- Isaac Sim 설치 경로는 `ISAAC_ROOT` 환경변수로 덮어쓸 수 있다. 기본값은
  `$HOME/dev_ws/isaac_sim/isaacsim/_build/linux-x86_64/release`.
- FastDDS `interfaceWhiteList` 는 IP 주소만 받는다 (Humble 의 FastDDS 2.6 기준).
  인터페이스 이름 지정은 불가하므로 고정 IP 가 전제 조건이다.

## 7. 범위 밖

- 무선(AP)을 ROS 전송로로 쓰는 비교 측정 — 유선 전용 구성만 검증한다
- 무선 NIC 의 DDS 트래픽 `tcpdump` 검증 — FastDDS `interfaceWhiteList` 가 인터페이스를
  이미 유선으로 묶으므로 별도 측정 단계로 두지 않는다
- end-to-end 지연 측정 — 시계 동기화 인프라가 없다
- SSH 오케스트레이션 — 각 노트북에서 수동 실행한다
- 계측 스크립트와 결과 취합 — 측정은 사용자가 직접 한다
- 다중 로봇(multi-carter) 시나리오
