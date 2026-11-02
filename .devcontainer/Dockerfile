# Devcontainer image: the chess stack for any member, from `git clone`.
# Based on osrf/ros:humble-desktop-full (athackst pattern) — desktop-full
# brings RViz and the GUI stack that plain ros:humble (CI image) lacks.
# That image is amd64 only. On a Raspberry Pi 5 (arm64) build from
# ros:humble-ros-base instead: no RViz, everything else the same
# (devcontainer.json reads it from ROS_BASE_IMAGE; docs/CHESS.md).
# The default lives here, not in devcontainer.json: ${localEnv:VAR:default}
# cuts the default at its first ':', which turned it into plain "osrf/ros".
ARG BASE_IMAGE
FROM ${BASE_IMAGE:-osrf/ros:humble-desktop-full}

# Mirrors the Jetson install (docs/JETSON.md step 3):
#   ros-humble-ur              driver + calibration + moveit config
#   ros-humble-moveit          motion planning
#   ros-humble-pick-ik         IK plugin lab_arm_moveit.launch.py can select
#                              (the chess stack runs KDL)
#   libnet1-dev                Modbus RTU/TCP dep for the vendored gripper
#                              hardware_interface (src/vendor, ur7e.repos)
#   rmw-cyclonedds-cpp         the RMW the Jetson runs — same middleware everywhere
#   stockfish                  the engine; without it lab_chess.py plays random
#                              legal moves (installs to /usr/games, chess_env.sh
#                              adds it to PATH)
RUN apt-get update && apt-get install -y --no-install-recommends \
    ros-humble-ur \
    ros-humble-moveit \
    ros-humble-pick-ik \
    libnet1-dev \
    ros-humble-rmw-cyclonedds-cpp \
    ros-humble-cv-bridge \
    ros-humble-message-filters \
    python3-opencv \
    python3-numpy \
    python3-scipy \
    python3-yaml \
    python3-pytest \
    xvfb \
    python3-colcon-common-extensions \
    python3-rosdep \
    python3-vcstool \
    python3-pip \
    gdb \
    git \
    nano \
    stockfish \
    && rm -rf /var/lib/apt/lists/*

# pip-only dependencies:
#   chess      - python-chess, the rules and the Stockfish bridge for
#                scripts/lab_chess.py (stockfish itself is apt, above).
#   pytest>=7  - apt's 6.2.5 aborts collection on a module-level
#                importorskip; the chess tests are written for 7+.
# Installed system-wide here (before USER switches) so every user in the
# image has them; --break-system-packages is not needed on 22.04.
RUN pip3 install --no-cache-dir "pytest>=7,<9" "chess>=1.10"

# Non-root user: files created in the bind-mounted workspace stay owned by
# you, not root (the classic Docker-on-Linux paper cut).
ARG USERNAME=ros
ARG USER_UID=1000
ARG USER_GID=$USER_UID
RUN groupadd --gid $USER_GID $USERNAME \
    && useradd --uid $USER_UID --gid $USER_GID -m $USERNAME -s /bin/bash \
    && apt-get update && apt-get install -y sudo \
    && echo "$USERNAME ALL=(root) NOPASSWD:ALL" > /etc/sudoers.d/$USERNAME \
    && chmod 0440 /etc/sudoers.d/$USERNAME \
    && rm -rf /var/lib/apt/lists/*

USER $USERNAME

# Shell environment for every terminal in the container.
# ROS_DOMAIN_ID + RMW match the Jetson (docs/JETSON.md): a laptop on the
# Jetson's hotspot sees its topics without any per-shell exports.
RUN echo 'source /opt/ros/humble/setup.bash' >> ~/.bashrc \
    && echo '[ -f /workspaces/*/install/setup.bash ] && source /workspaces/*/install/setup.bash' >> ~/.bashrc \
    && echo 'export ROS_DOMAIN_ID=42' >> ~/.bashrc \
    && echo 'export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp' >> ~/.bashrc
