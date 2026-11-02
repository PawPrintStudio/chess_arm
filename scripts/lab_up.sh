#!/usr/bin/env bash
# The chess stack in one command: driver -> MoveIt (KDL), each started in the
# background and waited on until it is really ready. Then play from another
# terminal (python3 scripts/lab_chess.py ..., docs/CHESS.md). Ctrl+C here
# stops MoveIt and the driver. No camera is started: chess plays from a
# square table; the camera (student's move, dashboard) is lab_chess.py's own.
#
# Run it twice, once per side:
#   bash scripts/lab_up.sh        # on the laptop HOST: link up, start VS Code
#   bash scripts/lab_up.sh        # in the DEV CONTAINER, or natively on the Jetson
#
#   LAB_SPEED=25 bash scripts/lab_up.sh                # reminder printed at the pendant step (default 100)
#   KEEP_STACK=true bash scripts/lab_up.sh             # leave driver/MoveIt up on exit
#
# CHESS=true (the old project's switch) is accepted and ignored: this script
# only knows the chess stack.
#
# It assumes nothing moved: lab_tooling.yaml (verified) and .console_poses.json
# (taught chess_home) are reused as they are. It never presses Play for you and
# never bypasses a check.
set -eo pipefail
cd "$(dirname "$0")/.."
ROBOT_IP=${ROBOT_IP:-192.168.56.101}
# The container has no ping. Opening the dashboard port (29999) works on
# both sides and also proves the controller itself is answering.
robot_reachable() { timeout 3 bash -c "exec 3<>/dev/tcp/$ROBOT_IP/29999" 2>/dev/null; }

# ---------------------------------------------------------------- host side
# The laptop host has no ROS; the Jetson runs Humble natively and takes the
# container branch below (docs/JETSON.md).
if [[ ! -f /.dockerenv && ! -f /opt/ros/humble/setup.bash ]]; then
  echo "== host: bringing up the robot link"
  nmcli con up "${UR_LINK:-ur-link}"
  robot_reachable || { echo "== no reply from $ROBOT_IP: check the cable and the pendant network" >&2; exit 2; }
  echo "   robot answers at $ROBOT_IP"
  code .
  echo "== in VS Code: Reopen in Container, then in its terminal:  bash scripts/lab_up.sh"
  exit 0
fi

# ----------------------------------------------------------- container side
# The host's .venv (Python 3.12) gets auto-activated in container terminals
# too; ROS here is 3.10. Drop it from PATH for everything this script starts.
if [[ -n "${VIRTUAL_ENV:-}" ]]; then
  PATH="$(tr ':' '\n' <<<"$PATH" | grep -vxF "$VIRTUAL_ENV/bin" | paste -sd:)"
  unset VIRTUAL_ENV
  echo "   ignoring the active .venv (host Python) for this run"
fi
source /opt/ros/humble/setup.bash
source install/setup.bash
source scripts/lab_env.sh
set -u
SPEED="${LAB_SPEED:-100}"
KEEP="${KEEP_STACK:-false}"
OUT="log/lab/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT"
echo "== logs: $OUT"

robot_reachable || { echo "== no reply from $ROBOT_IP: bring up the robot link (laptop host: nmcli con up ${UR_LINK:-ur-link}; Jetson: sudo nmcli con up ur-link-chess)" >&2; exit 2; }

# Two drivers means two controller managers fighting over the arm.
if pgrep -f "ur7e_bringup.launch.py|lab_arm_moveit.launch.py" >/dev/null; then
  echo "== part of the stack is already running:" >&2
  pgrep -af "ur7e_bringup.launch.py|lab_arm_moveit.launch.py" >&2
  echo "   stop it first (Ctrl+C its terminal, or pkill -f <name>), then rerun." >&2
  exit 2
fi

pids=()
start() {  # start <name> <command...>: own process group, log to $OUT/<name>.log
  local name="$1"; shift
  setsid "$@" >"$OUT/$name.log" 2>&1 &
  pids+=("$!")
}
cleanup() {
  if [[ "$KEEP" == true ]]; then
    echo "== stack left running (KEEP_STACK=true). Stop it with:  pkill -INT -f ur7e_bringup.launch.py; pkill -INT -f lab_arm_moveit.launch.py"
    return
  fi
  echo "== stopping MoveIt, driver"
  for (( i=${#pids[@]}-1; i>=0; i-- )); do kill -INT -- "-${pids[i]}" 2>/dev/null || true; done
  sleep 3
  for pid in "${pids[@]}"; do kill -KILL -- "-$pid" 2>/dev/null || true; done
}
trap cleanup EXIT

wait_until() {  # wait_until <seconds> <what> <log> <test...>
  local seconds="$1" what="$2" log="$3"; shift 3
  local deadline=$((SECONDS + seconds))
  until "$@" >/dev/null 2>&1; do
    if (( SECONDS >= deadline )); then
      echo "== TIMEOUT after ${seconds}s waiting for $what. Last lines of $OUT/$log.log:" >&2
      tail -n 25 "$OUT/$log.log" >&2; exit 3
    fi
    sleep 2
  done
  echo "   ready: $what"
}
has_service() { timeout 20 ros2 service list | grep -qx "$1"; }
controller_ready() {
  # The showcase image has controller_manager_msgs but not the ros2controlcli
  # plugin. Query the service directly and match the exact controller/state.
  timeout 20 python3 - "$1" <<'PY'
import sys
import rclpy
from controller_manager_msgs.srv import ListControllers

rclpy.init()
node = rclpy.create_node('lab_controller_readiness')
ready = False
allowed_states = ('active', 'inactive') if sys.argv[1] == 'configured' else ('active',)
try:
    client = node.create_client(ListControllers, '/controller_manager/list_controllers')
    if client.wait_for_service(timeout_sec=5.0):
        future = client.call_async(ListControllers.Request())
        rclpy.spin_until_future_complete(node, future, timeout_sec=5.0)
        if future.done() and future.result() is not None:
            ready = any(c.name == 'scaled_joint_trajectory_controller' and c.state in allowed_states
                        for c in future.result().controller)
finally:
    node.destroy_node()
    rclpy.shutdown()
sys.exit(0 if ready else 1)
PY
}
in_log() { grep -q "$2" "$OUT/$1.log"; }

echo "== 1/2 driver"
start driver ros2 launch ur7e_bringup ur7e_bringup.launch.py launch_rviz:=false
wait_until 90 "scaled_joint_trajectory_controller configured" driver controller_ready configured

echo
echo "   >>> Pendant: set the speed slider (it is the speed; cap ${SPEED} %), then press PLAY. <<<"
echo
wait_until 180 "pendant Play (reverse interface connected)" driver \
  in_log driver "Robot connected to reverse interface"
wait_until 30 "scaled_joint_trajectory_controller active" driver controller_ready active

echo "== 2/2 MoveIt (KDL)"
start moveit ros2 launch scripts/lab_arm_moveit.launch.py ik:=kdl
wait_until 120 "MoveIt (/compute_cartesian_path)" moveit has_service /compute_cartesian_path

echo "== chess stack up. In another terminal:  python3 scripts/lab_chess.py ...  (docs/CHESS.md)"
echo "   Ctrl+C here stops MoveIt and the driver."
wait -n "${pids[@]}" || true   # returns on Ctrl+C or when either one dies
exit 0
