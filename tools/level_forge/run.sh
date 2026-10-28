#!/bin/sh
# Regenerates level JSON from the artwork skeletons, then proves each result is solvable.
#
#   tools/level_forge/run.sh <outDir> <trials> <firstSeed> [levelID]
#
# To rebuild exactly the shipped levels:
#   level 1: seed 56    level 2: seed 13    level 3: seed 249     (trials 1)
# e.g. tools/level_forge/run.sh /tmp/levels 1 56 1
set -e
cd "$(dirname "$0")"
OUT="${1:?output directory}"; TRIALS="${2:-200}"; SEED="${3:-1}"; LEVEL="$4"
mkdir -p "$OUT" /tmp/pencil-hive-forge
python3 make_skeletons.py
python3 make_more_skeletons.py > /dev/null
swiftc -O -swift-version 5 ../../PencilHive/Core/*.swift main.swift -o /tmp/pencil-hive-forge/forge
/tmp/pencil-hive-forge/forge skeletons "$OUT" "$TRIALS" "$SEED" $LEVEL
