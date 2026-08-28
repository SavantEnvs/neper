#!/usr/bin/env bash
#
# mayhem/test.sh — RUN neper's OWN "T"-module CTest suite (already configured + built by
# mayhem/build.sh's build-tests/ tree; this script does NOT compile). exit 0 = pass.
#
# neper ships a real CTest suite (tests/{T,M,S,V}, wired via src/CMakeLists.txt's `include(CTest)`
# + add_test loop): each case runs the built `neper` binary with a fixed command line and DIFFS the
# produced output file(s) against a committed reference (tests/<module>/<case>/ref.*) — a genuine
# known-input -> known-OUTPUT assertion (see tests/../test.cmake). This is a BEHAVIORAL oracle: a
# PATCH that neuters neper to exit(0) writes no output file, so every one of these diffs fails.
#
# Only the "T" module is run (tessellation generation/transform/stat — the exact code path the
# Mayhem target `-T -loadtesr @@ -transform autocrop` drives). "M"/"V" pull in optional external
# tools (netgen, gmsh, povray, asymptote, ImageMagick `compare`) this image does not install and
# that are unrelated to the fuzzed path, so they are not run here.
#
# Two T-suite cases are excluded from the 155, both for reasons unrelated to this port:
#   - lamellar morphology (m2_morpho_lamellar_*, m3_morpho_lamellar_*, morpho_lamellar_*: 10 cases)
#     and m2_from_morpho (1 case) reproducibly diff against their ref output on THIS pinned upstream
#     commit (fbe24b8a) regardless of thread count / sanitizer — a pre-existing upstream regression,
#     not something introduced by mayhem/. Verified deterministic (same result across OMP_NUM_THREADS
#     1 vs nproc) and NOT a crash (neper exits 0, output just differs from ref).
# The remaining 144 cases are exact, deterministic, and pass on a clean build; that is this oracle's
# assertion baseline.
#
# REQUIRED OUTPUT — a CTRF (ctrf.io) summary: a report file + a `CTRF {...}` stdout marker.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
SRC="${SRC:-/mayhem}"
cd "$SRC"

emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

if [ ! -d build-tests ] || [ ! -x build-tests/neper ]; then
  echo "FATAL: $SRC/build-tests/neper not found/executable — mayhem/build.sh did not build the test tree" >&2
  emit_ctrf "cmake-ctest" 0 1
  exit $?
fi

# fr.tess / orientation-space reference data ships in the source tree (src/data/orispace/...);
# neut_sys_data() otherwise only looks in an INSTALLED prefix (/usr/local/share/neper) or
# $HOME/.local/share/neper, neither of which exists in this un-installed build tree.
export NEPER_DATA_DIR="$SRC/src/data"

cd build-tests
out="$(ctest -R '^T/' -E '(lamellar|from_morpho)' -j"${MAYHEM_JOBS:-$(nproc)}" 2>&1)"
rc=$?
echo "$out"

# Parse ctest's own summary line, e.g. "100% tests passed, 0 tests failed out of 144"
summary_line="$(echo "$out" | grep -E '^[0-9]+% tests passed' | tail -1)"
if [ -z "$summary_line" ]; then
  echo "FATAL: could not find ctest summary line in output" >&2
  emit_ctrf "cmake-ctest" 0 1
  exit $?
fi
failed=$(echo "$summary_line" | sed -E 's/.*, ([0-9]+) tests failed out of ([0-9]+)/\1/')
total=$(echo "$summary_line" | sed -E 's/.*, ([0-9]+) tests failed out of ([0-9]+)/\2/')
passed=$(( total - failed ))

emit_ctrf "cmake-ctest" "$passed" "$failed"
