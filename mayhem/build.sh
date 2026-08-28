#!/usr/bin/env bash
#
# mayhem/build.sh — build the neper CLI (a sanitizer-instrumented file-input target) + a clean,
# independent build carrying neper's own CTest suite (the "T" module — tessellation generation /
# transform / stats, i.e. the code path the Mayhem target actually exercises) for mayhem/test.sh.
#
# neper ships no LLVMFuzzerTestOneInput harness: Mayhem drives the whole CLI on a file input
# (`-T -loadtesr @@ -transform autocrop -o /tmp/...`, mirroring the historical mayhemheroes target).
# There is therefore no LIB_FUZZING_ENGINE link and no separate *-standalone binary — the sanitized
# CLI binary IS its own run-once reproducer (same pattern as z88dk's z80asm / genometools' gt).
#
# Env contract from the base image: CC/CXX, SANITIZER_FLAGS, DEBUG_FLAGS, MAYHEM_JOBS, SRC=/mayhem.
set -euo pipefail

# clang rejects SOURCE_DATE_EPOCH='' (empty) — it must be unset or a valid integer.
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX MAYHEM_JOBS COVERAGE_FLAGS

SRC="${SRC:-/mayhem}"
cd "$SRC"

# ---- (1) SANITIZED build -> /mayhem/neper (the fuzz/repro target) --------------------------------
# Instrument the project itself (not just a harness) with $SANITIZER_FLAGS + $DEBUG_FLAGS so Mayhem
# gets edge coverage AND DWARF < 4 symbols from the actual meshing/tessellation code. -DBUILD_TESTING=OFF:
# this configuration is for fuzzing only, the CTest suite is built separately below (step 2) with
# normal flags so mayhem/test.sh stays an honest, un-sanitized functional oracle.
cmake -S src -B build-fuzz -G Ninja \
  -DCMAKE_C_COMPILER="$CC" -DCMAKE_CXX_COMPILER="$CXX" \
  -DCMAKE_C_FLAGS="$SANITIZER_FLAGS $DEBUG_FLAGS" \
  -DCMAKE_CXX_FLAGS="$SANITIZER_FLAGS $DEBUG_FLAGS" \
  -DCMAKE_EXE_LINKER_FLAGS="$SANITIZER_FLAGS" \
  -DBUILD_TESTING=OFF
cmake --build build-fuzz -j"$MAYHEM_JOBS" --target neper
install -m 0755 build-fuzz/neper "$SRC/neper"

# ---- (2) NORMAL (clean, independent) build + neper's own CTest suite -----------------------------
# neper ships a real CTest suite (tests/{T,M,S,V}, wired via src/CMakeLists.txt's `include(CTest)`
# + add_test loop) that runs the built `neper` binary against fixed inputs and diffs the output
# against committed reference files (tests/*/*/ref.*) — a genuine known-input -> known-output
# oracle. mayhem/test.sh runs only the "T" subset (tessellation generation/transform/stat — the
# module the Mayhem target itself drives): M/V pull in optional external mesh/render tools (netgen,
# gmsh, povray, asymptote, ImageMagick `compare`) that this image does not install and that are
# unrelated to the fuzzed code path.
cmake -S src -B build-tests -G Ninja \
  -DCMAKE_C_COMPILER="$CC" -DCMAKE_CXX_COMPILER="$CXX" \
  -DCMAKE_C_FLAGS="$COVERAGE_FLAGS" -DCMAKE_CXX_FLAGS="$COVERAGE_FLAGS" \
  -DBUILD_TESTING=ON
cmake --build build-tests -j"$MAYHEM_JOBS" --target neper

echo "build.sh: built /mayhem/neper (sanitized) and build-tests/ (clean, CTest-ready)"
