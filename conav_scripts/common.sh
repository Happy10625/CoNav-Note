#!/usr/bin/env bash

# Shared ROS 2 environment for every Co-Nav2 terminal.
# ROS 2 Humble setup files legitimately inspect optional variables such as
# AMENT_TRACE_SETUP_FILES. Temporarily disable nounset while sourcing them,
# even when the calling script has already enabled `set -u`.
set +u

source /opt/ros/humble/setup.bash
source /home/isee-cdh/ros2_ws/install/setup.bash
# The L515-compatible RealSense build must override the incompatible copy in
# ros2_ws (the latter fails with undefined symbol rs2_create_context_ex).
source /home/isee-cdh/rs515/ros2_ws/install/setup.bash
source /home/isee-cdh/agilex_ws/install/setup.bash
source /home/isee-cdh/ws/install_fastlio/setup.bash
source /home/isee-cdh/ws/install_ros2/setup.bash

export RCUTILS_COLORIZED_OUTPUT=1
set -u
