# Running cafnusyst on justIN

This directory contains the scripts to package and run `cafnusyst` on the DUNE justIN grid system.

## Directory contents

- `submit_workflow.sh`: Submits a `justin simple-workflow`. Handles staging the package tarball and setting job options.
- `cafnusyst_justin.jobscript`: The script executed on worker nodes. Fetches input files with `justin-get-file` and runs `UpdateReweight`.
- `build_and_package.sh`: Compiles `cafnusyst` inside the standard SL7 container and bundles binaries, shared libraries, and spline tables into `cafnusyst_package.tar.gz`.
- `test_jobscript_interactive.sh`: Runs a local test of the jobscript on a few events inside Singularity.
- `fcl/`: Configuration FHiCL files (e.g. `systs_atmospherics_v2.fcl`).

---

## 1. Building the package

To build or update the deployment tarball (`cafnusyst_package.tar.gz`):

```bash
./build_and_package.sh --nusyst-dir /path/to/nusystematics/build
```

(If `$NUSYST_DIR` is set in your environment, `--nusyst-dir` can be omitted.)

This compiles `cafnusyst` against `duneanaobj v04_01_00` and bundles required `nusystematics` shared libraries, `setup_runtime.sh`, and custom MEC spline data into a standalone tarball.

---

## 2. Local testing

Before submitting to the grid, you can run a quick interactive test:

```bash
# Test 5 events on the default atmospheric CAF
./test_jobscript_interactive.sh "" 5

# Test a custom file
./test_jobscript_interactive.sh /path/to/input.root 10
```

---

## 3. Submitting to justIN

Make sure you have a valid justIN token:
```bash
justin get-token
justin whoami
```

### Dry-run check

Check the generated `justin simple-workflow` command:

```bash
./submit_workflow.sh \
  --mql "files from fardet-hd:fardet-hd-caf_3187 limit 2" \
  --dry-run
```

### Submitting jobs

```bash
./submit_workflow.sh \
  --mql "files from fardet-hd:fardet-hd-caf_3187 where core.file_type='caf' limit 5" \
  --scope usertests \
  --files-per-job 1 \
  --fcl systs_atmospherics_v2.fcl
```

*(For official atmospheric production CAFs, query `fardet-hd:fardet-hd__fdhd_he_2026a_caf__caf__v10_20_09d01__cafmaker_atmos_dune10kt_1x2x6_runreco-nuenergy-nuangular_geov5__prodgenie_atmnu_max_weighted_randompolicy_dune10kt_1x2x6__out1__v1_official`)*

If `cafnusyst_package.tar.gz` is not yet on dCache or is newer than the remote copy, `submit_workflow.sh` will automatically stage it to `/pnfs/dune/scratch/users/${USER}/cafnusyst_package.tar.gz`.

### Options

| Option | Description | Default |
| :--- | :--- | :--- |
| `--mql <query>` | MetaCat query for input CAFs | Sample CAF query |
| `--scope <scope>` | Rucio / justIN output scope | `usertests` |
| `--fcl <file>` | Systematic FHiCL file (in `fcl/`, local path, or `/pnfs`) | `systs_atmospherics_v2.fcl` |
| `--files-per-job <n>` | Files processed per grid job (`0` for unlimited) | `1` |
| `--package-url <path>`| dCache path or URL for `cafnusyst_package.tar.gz` | `/pnfs/dune/scratch/users/${USER}/...` |
| `--wall-seconds <sec>`| Maximum job walltime in seconds | `14400` (4h) |
| `--rss-mib <mib>` | Memory limit in MiB | `4000` (4 GB) |
| `--site <sitename>` | Restrict jobs to a specific site | Unset (any) |
| `--dry-run` | Print the command without submitting | `false` |

---

## 4. Notes

- **Outputs:** For each input file `<name>.root`, `cafnusyst` generates:
  - `<name>.cafnusyst.flat.root` (flat CAF)
  - `<name>.cafnusyst.nested.root` (nested CAF)
- **Files per job:** The default is 1 file per worker job. This allows justIN to distribute the workflow across worker nodes in parallel rather than serializing them on a single node.
- **Tree compatibility:** `WeightUpdater` auto-detects both root-level trees (`cafTree`) and subfolder trees (`cafmaker/cafTree`).
