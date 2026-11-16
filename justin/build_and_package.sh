#!/bin/bash
# ==============================================================================
# build_and_package.sh — Build cafnusyst and package for justIN execution
# ==============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CAFNUSYST_SRC="$(cd "${SCRIPT_DIR}/.." && pwd)"
OUTPUT_TARBALL="${SCRIPT_DIR}/cafnusyst_package.tar.gz"
PKG_DIR="/tmp/cafnusyst_pkg_$$"
trap 'rm -rf "$PKG_DIR"' EXIT

usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Options:
  --nusyst-dir <path>  Path to nusystematics build directory (or set \$NUSYST_DIR)
  --src-dir <path>     Path to cafnusyst source directory (Default: $CAFNUSYST_SRC)
  --output <path>      Output tarball path (Default: $OUTPUT_TARBALL)
  -h, --help           Show this help message
EOF
    exit 1
}

CODEDIR="${NUSYST_DIR:-}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --nusyst-dir) CODEDIR="$2"; shift 2;;
        --src-dir)    CAFNUSYST_SRC="$2"; shift 2;;
        --output)     OUTPUT_TARBALL="$2"; shift 2;;
        -h|--help)    usage;;
        *)            echo "Unknown option: $1"; usage;;
    esac
done

# If not explicitly specified, check user's local calculation directory
if [ -z "$CODEDIR" ] && [ -d "/exp/dune/app/users/${USER}/systematics-lars/atmospherics-tools/xsec_systs_calculation" ]; then
    CODEDIR="/exp/dune/app/users/${USER}/systematics-lars/atmospherics-tools/xsec_systs_calculation"
fi

if [ -z "$CODEDIR" ] || [ ! -d "$CODEDIR" ]; then
    echo "ERROR: nusystematics build directory not found!"
    echo "Please specify --nusyst-dir <path> or set the NUSYST_DIR environment variable."
    exit 1
fi

if [ ! -f "${CODEDIR}/build/Linux/bin/setup.nusystematics.sh" ]; then
    echo "ERROR: ${CODEDIR}/build/Linux/bin/setup.nusystematics.sh not found!"
    echo "--nusyst-dir must contain the nusystematics build/ directory (after 'make install')."
    exit 1
fi

# A standard nusystematics build (see README.md) uses the UPS fhiclcpp product;
# only a build that compiled fhicl-cpp-standalone in-tree provides this script.
if [ -f "${CODEDIR}/build/Linux/bin/setup.fhicl_cpp_standalone.sh" ]; then
    CAFNUSYST_FHICLCPP="standalone"
else
    CAFNUSYST_FHICLCPP="ups"
fi

echo "Building cafnusyst: $CAFNUSYST_SRC"
echo "Using nusystematics: $CODEDIR (fhiclcpp: $CAFNUSYST_FHICLCPP)"

# 1. Compile cafnusyst inside standard SL7 container using setup_runtime.sh as base
singularity exec \
  --env "SCRIPT_DIR=${SCRIPT_DIR}" \
  --env "CODEDIR=${CODEDIR}" \
  --env "CAFNUSYST_SRC=${CAFNUSYST_SRC}" \
  --env "CAFNUSYST_FHICLCPP=${CAFNUSYST_FHICLCPP}" \
  -B /cvmfs,/exp,/pnfs \
  /cvmfs/singularity.opensciencegrid.org/fermilab/fnal-wn-sl7:latest bash -s <<'BUILD_SCRIPT'
source "${SCRIPT_DIR}/setup_runtime.sh"
set -e
setup cmake v3_27_4

if [ "${CAFNUSYST_FHICLCPP}" = "standalone" ]; then
    source "${CODEDIR}/build/Linux/bin/setup.fhicl_cpp_standalone.sh"
fi
source "${CODEDIR}/build/Linux/bin/setup.systematicstools.sh"
source "${CODEDIR}/build/Linux/bin/setup.nusystematics.sh"

mkdir -p "${CAFNUSYST_SRC}/build"
cd "${CAFNUSYST_SRC}/build"
cmake ../ -DCMAKE_INSTALL_PREFIX="${CAFNUSYST_SRC}/install" \
  -DSQLite3_LIBRARY="${SQLITE_LIB}/libsqlite3_ups.so"
make -j8 install
BUILD_SCRIPT

# 2. Assemble deployment package
echo "Assembling deployment package..."
rm -rf "${PKG_DIR}"
mkdir -p "${PKG_DIR}/bin" "${PKG_DIR}/lib" "${PKG_DIR}/fcl" "${PKG_DIR}/mec_data"

# Binaries and libraries
cp -a "${CAFNUSYST_SRC}/install/bin/"* "${PKG_DIR}/bin/"
cp -a "${CAFNUSYST_SRC}/install/lib/"*.so* "${PKG_DIR}/lib/"

# nusystematics libraries and setup scripts
cp -a "${CODEDIR}/build/Linux/lib/"* "${PKG_DIR}/lib/"
cp -a "${CODEDIR}/build/Linux/bin/"setup.*.sh "${PKG_DIR}/bin/"

# Custom MEC splines and hadron tensors (if present)
if [ -f "${CODEDIR}/custom_mec_splines_ar40.xml" ]; then
    cp -a "${CODEDIR}/custom_mec_splines_ar40.xml" "${PKG_DIR}/mec_data/"
fi
if [ -d "${CODEDIR}/genie_config" ]; then
    cp -a "${CODEDIR}/genie_config" "${PKG_DIR}/mec_data/"
fi

# Data read by the non-GENIE providers through ${NUSYST_DATA_DIR} (DUNE v0 config),
# from a pinned NuSystematics/nusyst_data release. QEFix is 5.5 GB there; its
# h_weights_map histograms are identical to sbndata's QE-Fix, so link that instead.
NUSYST_DATA_REPO="https://github.com/NuSystematics/nusyst_data"
NUSYST_DATA_TAG="v01_00_00"
mkdir -p "${PKG_DIR}/nusyst_data/ValenciaExc2p2hReweighter"
while read -r asset sha; do
    curl -sSfL -o "${PKG_DIR}/${asset}.tar.gz" "${NUSYST_DATA_REPO}/releases/download/${NUSYST_DATA_TAG}/${asset}.tar.gz"
    echo "${sha}  ${PKG_DIR}/${asset}.tar.gz" | sha256sum -c --quiet -
    mkdir -p "${PKG_DIR}/nusyst_data/${asset}"
    tar -xzf "${PKG_DIR}/${asset}.tar.gz" -C "${PKG_DIR}/nusyst_data/${asset}"
    rm -f "${PKG_DIR}/${asset}.tar.gz"
done <<'EOF'
CCQEReweight d40bdca7af2740f84cf40c7aa6274bb11eeb916926d8017caee86703a72cfcbe
CCMEC_template b42a93cf49bc911b4662474aba380ea0355b0d62af2546877f445ff609a196e0
QEInterference d67e52031913631ce8d22ef2016c680f197a53907f14a65ab9b2fbde1e888dcf
EOF
while read -r json sha; do
    f="${PKG_DIR}/nusyst_data/ValenciaExc2p2hReweighter/${json}"
    curl -sSfL -o "$f" "https://raw.githubusercontent.com/NuSystematics/nusyst_data/${NUSYST_DATA_TAG}/ValenciaExc2p2hReweighter/${json}"
    echo "${sha}  ${f}" | sha256sum -c --quiet -
done <<'EOF'
ICARUS_BNB_numu_C12_SuSAv2_to_ValenciaExclusive_2p2h_pn_bdtreweighter.json 93fb3db4ab57cda32673b52f78ce2a848ddf4f5a9d317c113fb469b4c543cc07
ICARUS_BNB_numu_C12_SuSAv2_to_ValenciaExclusive_2p2h_pp_bdtreweighter.json 5e8351fd8bbd7c54b6fa8504bfdbb37fdc8f0483dc96173ba371222005a7cb94
EOF
ln -s /cvmfs/sbn.opensciencegrid.org/products/sbn/sbndata/v01_10/systematics/AR23Plus/QE-Fix "${PKG_DIR}/nusyst_data/QEFix"

# FHiCL configurations and runtime setup
cp -a "${SCRIPT_DIR}/fcl/"*.fcl "${PKG_DIR}/fcl/"
cp -a "${SCRIPT_DIR}/setup_runtime.sh" "${PKG_DIR}/setup_runtime.sh"
chmod +x "${PKG_DIR}/setup_runtime.sh"
if [ "${CAFNUSYST_FHICLCPP}" = "ups" ]; then
    touch "${PKG_DIR}/.fhiclcpp_ups"
fi

# 3. Create tarball
echo "Creating package tarball: $OUTPUT_TARBALL"
mkdir -p "$(dirname "$OUTPUT_TARBALL")"
tar -czf "$OUTPUT_TARBALL" -C "${PKG_DIR}" .
echo "Package ready ($(du -sh "$OUTPUT_TARBALL" | cut -f1))"
