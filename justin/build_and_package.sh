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

echo "Building cafnusyst: $CAFNUSYST_SRC"
echo "Using nusystematics: $CODEDIR"

# 1. Compile cafnusyst inside standard SL7 container using setup_runtime.sh as base
singularity exec \
  --env "SCRIPT_DIR=${SCRIPT_DIR}" \
  --env "CODEDIR=${CODEDIR}" \
  --env "CAFNUSYST_SRC=${CAFNUSYST_SRC}" \
  -B /cvmfs,/exp,/pnfs \
  /cvmfs/singularity.opensciencegrid.org/fermilab/fnal-wn-sl7:latest bash -s <<'BUILD_SCRIPT'
source "${SCRIPT_DIR}/setup_runtime.sh"
set -e
setup cmake v3_27_4

source "${CODEDIR}/build/Linux/bin/setup.fhicl_cpp_standalone.sh"
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

# FHiCL configurations and runtime setup
cp -a "${SCRIPT_DIR}/fcl/"*.fcl "${PKG_DIR}/fcl/"
cp -a "${SCRIPT_DIR}/setup_runtime.sh" "${PKG_DIR}/setup_runtime.sh"
chmod +x "${PKG_DIR}/setup_runtime.sh"

# 3. Create tarball
echo "Creating package tarball: $OUTPUT_TARBALL"
mkdir -p "$(dirname "$OUTPUT_TARBALL")"
tar -czf "$OUTPUT_TARBALL" -C "${PKG_DIR}" .
echo "Package ready ($(du -sh "$OUTPUT_TARBALL" | cut -f1))"
