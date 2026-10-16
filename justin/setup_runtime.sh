#!/bin/bash
# ==============================================================================
# setup_runtime.sh — Grid worker runtime environment for cafnusyst
# ==============================================================================
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 1. UPS Products
unset LD_LIBRARY_PATH
source /cvmfs/dune.opensciencegrid.org/products/dune/setup_dune.sh
setup duneanaobj v04_01_00 -q e26:prof
setup genie v3_04_02 -q e26:prof
setup genie_xsec v3_04_00 -q AR2320i00000:e1000:k250
setup boost v1_80_0 -q e26:prof
setup eigen v23_08_01_66e8f
setup sqlite v3_40_01_00
export PRODUCTS=$PRODUCTS:/cvmfs/sbn.opensciencegrid.org/products/sbn
setup sbndata v01_10

# 2. Package paths
export PATH="${BASE_DIR}/bin:${PATH}"
export LD_LIBRARY_PATH="${BASE_DIR}/lib:${LD_LIBRARY_PATH}"
export FHICL_FILE_PATH=".:${BASE_DIR}/fcl:${BASE_DIR}/mec_data:${FHICL_FILE_PATH}"

# 3. Custom CC-MEC Hadron Tensors & Splines (if present in package)
if [ -d "${BASE_DIR}/mec_data/genie_config" ]; then
    WORKDIR="${TMPDIR:-/tmp}/genie_work_${USER:-user}_$$"
    mkdir -p "${WORKDIR}/genie_config"
    ORIG_GENIE=$GENIE
    export GINUKEHADRONDATA="${ORIG_GENIE}/data/evgen/intranuke"

    ln -s "${BASE_DIR}/mec_data/genie_config/config" "${WORKDIR}/genie_config/config"
    mkdir -p "${WORKDIR}/genie_config/data/evgen/hadron_tensors"

    for p in ${ORIG_GENIE}/data/*; do
        bn=$(basename "$p"); [ "$bn" = "evgen" ] && continue
        ln -sfn "$p" "${WORKDIR}/genie_config/data/$bn"
    done
    for p in ${ORIG_GENIE}/data/evgen/*; do
        bn=$(basename "$p"); [ "$bn" = "hadron_tensors" ] && continue
        ln -sfn "$p" "${WORKDIR}/genie_config/data/evgen/$bn"
    done
    for p in ${ORIG_GENIE}/data/evgen/hadron_tensors/*; do
        ln -sfn "$p" "${WORKDIR}/genie_config/data/evgen/hadron_tensors/$(basename "$p")"
    done
    if [ -d "${BASE_DIR}/mec_data/genie_config/hadron_tensors_custom/martini" ]; then
        ln -sfn "${BASE_DIR}/mec_data/genie_config/hadron_tensors_custom/martini" "${WORKDIR}/genie_config/data/evgen/hadron_tensors/martini"
    fi

    export GENIE="${WORKDIR}/genie_config"
    export GENIE_REWEIGHT="${WORKDIR}/genie_config"
fi

if [ -f "${BASE_DIR}/mec_data/custom_mec_splines_ar40.xml" ]; then
    export CUSTOM_MEC_SPLINES_XML="${BASE_DIR}/mec_data/custom_mec_splines_ar40.xml"
fi

echo "Runtime environment ready: UpdateReweight -> $(command -v UpdateReweight)"
