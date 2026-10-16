#!/bin/bash
# ==============================================================================
# test_jobscript_interactive.sh — Test cafnusyst jobscript locally
# ==============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_FILE="${1:-/pnfs/dune/persistent/physicsgroups/duneatmexot/AtmInputs/prodgenie_atmnu_max_weighted_randompolicy_dune10kt_1x2x6_fdhd_he_2026a_reco2_v10_20_09d01_cafmaker_atmos_dune10kt_1x2x6_runreco-nuenergy-nuangular_geov5_caf_102005d01_v1_s001000_l001000_20260624T131644_caf_wWeights.root}"
N_EVENTS="${2:-10}"
TEST_FCL="${3:-systs_atmospherics_v2.fcl}"

if [ ! -f "$TEST_FILE" ]; then
    echo "ERROR: Test file not found: $TEST_FILE"
    exit 1
fi

if [ ! -f "${SCRIPT_DIR}/cafnusyst_package.tar.gz" ]; then
    echo "Building package first..."
    "${SCRIPT_DIR}/build_and_package.sh"
fi

TEST_DIR="/tmp/test_cafnusyst_$$"
mkdir -p "${TEST_DIR}"
cd "${TEST_DIR}"

echo "Testing cafnusyst jobscript on $(basename "$TEST_FILE") ($N_EVENTS events)..."
tar -xzf "${SCRIPT_DIR}/cafnusyst_package.tar.gz"

singularity exec \
    --env "MAX_EVENTS=${N_EVENTS}" \
    --env "CAFNUSYST_FCL=${TEST_FCL}" \
    -B /cvmfs,/exp,/pnfs,/tmp \
    /cvmfs/singularity.opensciencegrid.org/fermilab/fnal-wn-sl7:latest \
    "${SCRIPT_DIR}/cafnusyst_justin.jobscript" "$TEST_FILE"

echo "Test complete. Generated files in ${TEST_DIR}:"
ls -lh *.cafnusyst.*.root 2>/dev/null || true
