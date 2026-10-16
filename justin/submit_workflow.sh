#!/bin/bash
# ==============================================================================
# submit_workflow.sh — Submit cafnusyst systematic workflow to justIN
# ==============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JOBSCRIPT="${SCRIPT_DIR}/cafnusyst_justin.jobscript"
PACKAGE_TARBALL="${SCRIPT_DIR}/cafnusyst_package.tar.gz"

# Defaults
DEFAULT_MQL="files from dune:all where core.file_type='caf' limit 10"
DEFAULT_SCOPE="usertests"
DEFAULT_FCL="systs_atmospherics_v2.fcl"
DEFAULT_FILES_PER_JOB=1
DEFAULT_WALL_SECONDS=14400
DEFAULT_RSS_MIB=4000
DEFAULT_PACKAGE_URL="/pnfs/dune/scratch/users/${USER}/cafnusyst_package.tar.gz"

usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Options:
  --mql <query>          MetaCat query for input CAFs (Default: "$DEFAULT_MQL")
  --fcl <file>           Systematic FHiCL file (Default: "$DEFAULT_FCL")
  --files-per-job <n>    Number of files per worker job (Default: $DEFAULT_FILES_PER_JOB, 0 = unlimited)
  --scope <scope>        Rucio/justIN scope (Default: "$DEFAULT_SCOPE")
  --package-url <path>   Tarball path or URL (Default: "$DEFAULT_PACKAGE_URL")
  --wall-seconds <sec>   Job walltime limit in seconds (Default: $DEFAULT_WALL_SECONDS)
  --rss-mib <mib>        Memory limit in MiB (Default: $DEFAULT_RSS_MIB)
  --site <sitename>      Restrict to specific site (e.g. US_FNAL-FermiGrid)
  --dry-run              Print the generated command without submitting
  -h, --help             Show this help message
EOF
    exit 1
}

MQL="$DEFAULT_MQL"
SCOPE="$DEFAULT_SCOPE"
FCL_ARG="$DEFAULT_FCL"
FILES_PER_JOB="$DEFAULT_FILES_PER_JOB"
PACKAGE_URL="$DEFAULT_PACKAGE_URL"
WALL_SECONDS="$DEFAULT_WALL_SECONDS"
RSS_MIB="$DEFAULT_RSS_MIB"
SITE=""
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --mql)           MQL="$2"; shift 2;;
        --fcl)           FCL_ARG="$2"; shift 2;;
        --files-per-job) FILES_PER_JOB="$2"; shift 2;;
        --scope)         SCOPE="$2"; shift 2;;
        --package-url)   PACKAGE_URL="$2"; shift 2;;
        --wall-seconds)  WALL_SECONDS="$2"; shift 2;;
        --rss-mib)       RSS_MIB="$2"; shift 2;;
        --site)          SITE="$2"; shift 2;;
        --dry-run)       DRY_RUN=true; shift;;
        -h|--help)       usage;;
        *)               echo "Unknown option: $1"; usage;;
    esac
done

# Resolve FHiCL: if a local path is given, copy into fcl/ directory
if [ -f "$FCL_ARG" ]; then
    FCL_BASENAME="$(basename "$FCL_ARG")"
    if [ ! -f "${SCRIPT_DIR}/fcl/${FCL_BASENAME}" ]; then
        echo "Copying custom FHiCL '$FCL_ARG' into ${SCRIPT_DIR}/fcl/..."
        cp -a "$FCL_ARG" "${SCRIPT_DIR}/fcl/"
    fi
    FCL_TARGET="$FCL_BASENAME"
else
    FCL_TARGET="$FCL_ARG"
fi

# Build tarball if not present locally
if [ ! -f "$PACKAGE_TARBALL" ] && [ "$DRY_RUN" = false ]; then
    echo "Local package tarball not found. Building now..."
    "${SCRIPT_DIR}/build_and_package.sh"
fi

# Stage local tarball to dCache scratch if using default PNFS location
if [ -f "$PACKAGE_TARBALL" ] && [[ "$PACKAGE_URL" == /pnfs/* ]] && [ "$DRY_RUN" = false ]; then
    if [ ! -f "$PACKAGE_URL" ] || [ "$PACKAGE_TARBALL" -nt "$PACKAGE_URL" ]; then
        echo "Staging cafnusyst package to $PACKAGE_URL..."
        mkdir -p "$(dirname "$PACKAGE_URL")" 2>/dev/null || true
        rm -f "$PACKAGE_URL" 2>/dev/null || true
        if command -v ifdh &>/dev/null; then
            ifdh cp "$PACKAGE_TARBALL" "$PACKAGE_URL" || cp -f "$PACKAGE_TARBALL" "$PACKAGE_URL"
        else
            cp -f "$PACKAGE_TARBALL" "$PACKAGE_URL"
        fi
    fi
fi

# Set up justin if needed
if ! command -v justin &>/dev/null; then
    source /cvmfs/dune.opensciencegrid.org/products/dune/setup_dune.sh 2>/dev/null || true
    setup justin 2>/dev/null || true
fi

CMD=(
    justin simple-workflow
    --jobscript "$JOBSCRIPT"
    --mql "$MQL"
    --scope "$SCOPE"
    --rss-mib "$RSS_MIB"
    --wall-seconds "$WALL_SECONDS"
    --processors 1
    --max-distance 100
    --output-pattern "*.cafnusyst.*.root"
    --lifetime-days 7
    --env "FILES_PER_JOB=${FILES_PER_JOB}"
    --env "CAFNUSYST_FCL=${FCL_TARGET}"
    --env "PACKAGE_TARBALL_URL=${PACKAGE_URL}"
)

if [ -n "$SITE" ]; then
    CMD+=(--site "$SITE")
fi

echo "----------------------------------------------------------"
echo "Submitting to justIN:"
echo "  MQL:           $MQL"
echo "  Scope:         $SCOPE"
echo "  FHiCL:         $FCL_TARGET"
echo "  Files/Job:     $FILES_PER_JOB"
echo "  Package:       $PACKAGE_URL"
echo "  Walltime/RSS:  ${WALL_SECONDS}s / ${RSS_MIB} MiB"
[ -n "$SITE" ] && echo "  Site:          $SITE"
echo "----------------------------------------------------------"

if [ "$DRY_RUN" = true ]; then
    echo "[dry-run] ${CMD[*]}"
    exit 0
fi

"${CMD[@]}"
