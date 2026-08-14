"""nova_carter warehouse 씬을 로드하고 바로 Play 해 ROS 2 토픽 발행을 시작한다."""

from isaacsim import SimulationApp

simulation_app = SimulationApp({"headless": False})

from isaacsim.core.utils.extensions import enable_extension

enable_extension("isaacsim.ros2.bridge")
simulation_app.update()

import time
from pathlib import Path

import omni.timeline
import omni.usd
from pxr import UsdGeom

USD_PATH = str(Path(__file__).resolve().parent / "scenes/carter_warehouse_navigation.usd")

# /World prim 생성 후 USD Reference 연결
stage = omni.usd.get_context().get_stage()
UsdGeom.Xform.Define(stage, "/World")
world_prim = stage.GetPrimAtPath("/World")
world_prim.GetReferences().AddReference(USD_PATH)

# 씬 하위 에셋은 NVIDIA S3 에서 받아온다 — 첫 실행은 인터넷이 필요하고 느리다
for _ in range(60):
    simulation_app.update()

omni.timeline.get_timeline_interface().play()
print("\n[ready] 씬 재생 시작 — ROS 2 토픽 발행 중")

while simulation_app.is_running():
    simulation_app.update()
    time.sleep(0.016)

simulation_app.close()
