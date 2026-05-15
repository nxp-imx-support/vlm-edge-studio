#!/bin/bash

# Copyright 2026 NXP
# SPDX-License-Identifier: BSD-3-Clause 

export DISPLAY=:0

xterm \
  -bg "#0000CD" \
  -fg "#FFD700" \
  -cr "#FFFF00" \
  -geometry 100x20 \
  -title "VLM Edge Studio" \
  -e bash -c "
    echo '=======================================================';
    echo '      VLM Edge Studio is loading, please wait...';
    echo '=======================================================';
    echo 'Remember to set date/time to download models.';
    echo ''; date; echo '';
    run_vlm_edge_studio &
    APP_PID=\$!;
    while ! xdotool search --name 'VLM Edge Studio' 2>/dev/null | grep -qv \$\$; do
      sleep 0.5;
    done;
    exit 0
  " &
wait