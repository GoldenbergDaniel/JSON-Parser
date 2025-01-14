#!/bin/bash
set -e

# --- CONFIGURE ---------------------------------------------------------------------

MODE="dev"
if [[ $1 != "" ]]; then MODE=$1; fi
if [[ $MODE != "dev" && $MODE != "debug" && $MODE != "release" ]]; then
  echo "Failed to build. '$MODE' is not valid mode."
  exit 1
fi

TARGET="linux_amd64"
if [[ $2 != "" ]]; then TARGET=$2; fi
if [[ $TARGET != "darwin_amd64" && $TARGET != "darwin_arm64" && $TARGET != "linux_amd64" ]]; then
  echo "Failed to build. '$TARGET' is not a valid target."
  exit 1
fi

FLAGS="-collection:src=src $3"
if [[ $MODE == "dev"     ]]; then FLAGS="-o:none -use-separate-modules $FLAGS"; fi
if [[ $MODE == "debug"   ]]; then FLAGS="-o:none -debug $FLAGS"; fi
if [[ $MODE == "release" ]]; then FLAGS="-o:speed -no-bounds-check $FLAGS"; fi

echo [target:$TARGET]
echo [mode:$MODE]

# --- BUILD -------------------------------------------------------------------------

echo [build]

mkdir -p out
odin build src -out:out/parser -target:$TARGET $FLAGS
if [[ $MODE == "dev" ]]; then out/parser; fi
