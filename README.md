# Chess on the UR7e

A UR7e with an OnRobot RG2 plays chess against a student. python-chess for
the rules, Stockfish for the move, MoveIt (KDL) for the motion, one ZED
camera to read the student's move. Runs natively on the makerspace Jetson or
in the dev container on a laptop.

This repository is the chess workflow on its own, extracted from
[ur7e-language-pick-and-place](https://github.com/PawPrintStudio/ur7e-language-pick-and-place)
at commit `2feee8c` (2026-11-02). That repo keeps the full history, the
language-directed pick, the simulation tiers and the lab records that led
here; nothing in this one depends on it. The READMEs inside `src/` still
cite that repo's design and lab documents (ARCHITECTURE, RUNBOOK, TASK2);
read them there.

## Start here

- [docs/CHESS.md](docs/CHESS.md) — what the arm does, the commands, the
  calibration order, the improvement list
- [docs/JETSON.md](docs/JETSON.md) — setup on the shared Jetson, once
- [docs/JETSON_GAME_WORKBOOK.md](docs/JETSON_GAME_WORKBOOK.md) — a game,
  start to shut down, offline
- [docs/CHESS_OPERATOR_WALKTHROUGH.md](docs/CHESS_OPERATOR_WALKTHROUGH.md) —
  the laptop + container variant, screen by screen

## Layout

```
scripts/lab_chess.py       the game: touch, fit, goto, move, play, dashboard
scripts/chess_vision.py    the student's move from the camera (before/after)
scripts/chess_gestures.py  reactions
scripts/chess_voice.py     one spoken line per event (Ollama + Piper, host side)
scripts/lab_up.sh          driver + MoveIt in one command
scripts/chess_env.sh       source once per terminal
scripts/lab_pick.py, lab_jog.py, lab_tooling.py, motion/   the proven motion stages chess reuses
src/                       the ROS 2 packages (bringup, MoveIt config, orchestrator, perception, interfaces)
ur7e.repos                 pinned third-party UR+RG2 packages, fetched by scripts/vendor_import.sh
docs/evidence/chess-2026-10-14/   the calibration files of the showcase (copy into scripts/, JETSON.md step 6)
```

## Without the robot

```
cd scripts && PYTHONPATH=$PYTHONPATH:../src/ur7e_perception python3 -m pytest -q \
  -p no:launch_testing -p no:launch_ros \
  test_lab_chess.py test_chess_operator.py test_chess_vision.py test_chess_gestures.py test_chess_voice.py
python3 scripts/lab_chess.py play --steps-only --engine none    # the match loop in the terminal
```

Needs `pip install chess`, numpy, OpenCV, PyYAML. The dev container
(`.devcontainer/`) has everything, Stockfish included; on the Jetson follow
[docs/JETSON.md](docs/JETSON.md).

## With the robot

```
bash scripts/lab_up.sh                                   # driver, pendant Play, MoveIt
python3 scripts/lab_chess.py goto e4 --touch             # plan only
python3 scripts/lab_chess.py play --execute --max-speed-percent 25
```

Nothing moves without `--execute`. First moves of a session: slider low,
speed 25 %, every step confirmed ([docs/CHESS.md](docs/CHESS.md)).
