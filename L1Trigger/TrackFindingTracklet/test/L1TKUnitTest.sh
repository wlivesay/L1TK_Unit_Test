#!/bin/bash
trap 'rm -f "$TEST_DIR"/job_*_cfg.py' EXIT
set -e

# =============================================================================
# L1 Track CI - Master Unit Test
#
# Stages:
#   1. Compile + Run       (compile, run cmsRun N events per algorithm)
#   2. Analysis            (makeHists.csh + threshold validation)
#
# NOTE: Code style checks (auto-formatter, clang-tidy) are intentionally NOT
# implemented here. They are already covered by the CMS-wide "code-checks"
# unit test that runs on every CMSSW PR.
#
# Each algorithm runs against ONE dataset only (not both, to keep runtime
# down -- 3 cmsRun jobs instead of 6):
#   HYBRID           -> ttbar+PU200   (prompt tracking)
#   HYBRID_NEWKF     -> ttbar+PU200   (prompt tracking)
#   HYBRID_DISPLACED -> displacedSUSY+PU200 (displaced tracking)
#
# COMMAND-LINE ARGS:
#   -e <num-events>     number of events to run per algorithm (default: 10)
#   -j <parallel-jobs>  threads/streams cmsRun uses internally (default: 1)
#
# NOTE: threshold validation in Stage 2 only runs when EVENTS >= 1000, since
# the reference thresholds were calibrated at 1000 events -- lower stats
# would make those comparisons unreliable. Light/quick runs (EVENTS < 1000)
# still execute cmsRun + makeHists.csh as a smoke test, just without the
# physics threshold comparison. See Stage 2 below.
#
# HOW TO USE:
#   cd ~/<your CMSSW area>/src/
#   cmsenv
#   bash L1TKUnitTest.sh -e <num-events> -j <parallel-jobs>
#   (defaults: -e 10 -j 1 if omitted)
# Can instead run 'official' local unit test by adding L1TKUnitTest.sh to src/.../test/BuildFile.xml
# Then run scram b runtests to run all 'registered' unit tests (from BuildFile.xml)
# =============================================================================

# =============================================================================
# CONFIGURATION - update when CMSSW version or dataset changes
# =============================================================================
# CMSSW_VERSION is set automatically by cmsenv, so this is environment-agnostic
# and doesn't need manual updating per release.
CMSSW_IB="${CMSSW_VERSION}"
BRANCH_DEFAULT="L1TK-dev-${CMSSW_VERSION#CMSSW_}"
GITHUB_USER_DEFAULT="cms-L1TK"
# GITHUB_USER_UNDER_TEST and BRANCH_UNDER_TEST set automatically by cms-bot

CFG_FILE="L1TrackNtupleMaker_cfg.py"
TEST_DIR="$CMSSW_BASE/src/L1Trigger/TrackFindingTracklet/test"

# Set to "false" to also run HYBRID_NEWKF and HYBRID_DISPLACED.
# When "true", only HYBRID (on ttbar+PU200) is run.
QUICK_TEST="false"

# =============================================================================
# COMMAND-LINE ARGS
#   -e <num-events>    number of events to run per algorithm
#   -j <parallel-jobs>  threads/streams cmsRun uses internally
# =============================================================================
EVENTS=10
JOBS=1

while getopts "e:j:" opt; do
    case "$opt" in
        e) EVENTS="$OPTARG" ;;
        j) JOBS="$OPTARG" ;;
    esac
done

# =============================================================================
# MC DATASETS
# ttbar+PU200 checks prompt tracking (HYBRID, HYBRID_NEWKF).
# displacedSUSY+PU200 checks displaced tracking (HYBRID_DISPLACED).
# Both are 1k-event skims of official RelVal MC, produced by running
# L1Trigger/TrackFindingTracklet/test/skimForCI_cfg.py on the full samples.
#
# These are public CERNBox links, streamed directly by cmsRun (no grid
# certificate needed -- that would only be required for genuine XROOTD/EOS
# grid paths, which these are not). Update these URLs roughly once per year
# as the L1 tracking evolves and a newer MC production round is skimmed.
# Last updated: July 2026
# =============================================================================
MC_DATASET_PROMPT="https://cernbox.cern.ch/remote.php/dav/public-files/hzqCOI7gHA2eLhY/skimmed_ttbar_PU200_20_0_0.root"
MC_DESCRIPTION_PROMPT="1k events of /RelValTTbar_14TeV/CMSSW_20_0_0_pre1-PU_150X_mcRun4_realistic_v1_STD_D121_RegeneratedGS_PU-v1/GEN-SIM-DIGI-RAW"
MC_DATASET_DISPLACED="https://cernbox.cern.ch/remote.php/dav/public-files/kE5Fst5yNXkdbfm/skimmed_displacedSUSY_PU200_20_0_0.root"
MC_DESCRIPTION_DISPLACED="1k events of /RelValDisplacedSUSY_14TeV/CMSSW_20_0_0_pre1-PU_150X_mcRun4_realistic_v1_STD_D121_RegeneratedGS_PU-v1/GEN-SIM-DIGI-RAW"

# =============================================================================
# REFERENCE AND THRESHOLD VALUES
# Threshold roughly 3-sigma off from reference (should be checked over)
# Reference values should be updated based on the previous PR performance
# Currently hard-coded and should be updated manually once a year
# Last updated: July 2026
# =============================================================================

# --- HYBRID (ttbar+PU200) ---
HYBRID_EFFI_ETA_LOW_REFERENCE="94.47"       HYBRID_EFFI_ETA_LOW_THRESHOLD="93.87"
HYBRID_EFFI_ETA_MID_REFERENCE="93.77"       HYBRID_EFFI_ETA_MID_THRESHOLD="92.90"
HYBRID_EFFI_ETA_HIGH_REFERENCE="94.72"      HYBRID_EFFI_ETA_HIGH_THRESHOLD="93.61"
HYBRID_EFFI_PT2_REFERENCE="94.31"           HYBRID_EFFI_PT2_THRESHOLD="93.86"
HYBRID_EFFI_PT2TO8_REFERENCE="94.11"        HYBRID_EFFI_PT2TO8_THRESHOLD="93.57"
HYBRID_EFFI_PT8_REFERENCE="94.89"           HYBRID_EFFI_PT8_THRESHOLD="94.02"
HYBRID_EFFI_PT40_REFERENCE="93.81"          HYBRID_EFFI_PT40_THRESHOLD="90.54"
HYBRID_TP_PT2_REFERENCE="157.01"            HYBRID_TP_PT2_THRESHOLD="155.82"
HYBRID_TP_PT3_REFERENCE="51.46"             HYBRID_TP_PT3_THRESHOLD="50.78"
HYBRID_TP_PT10_REFERENCE="4.73"             HYBRID_TP_PT10_THRESHOLD="4.52"
HYBRID_NTRK_PT2_REFERENCE="175.41"          HYBRID_NTRK_PT2_THRESHOLD="176.67"
HYBRID_NTRK_PT3_REFERENCE="60.56"           HYBRID_NTRK_PT3_THRESHOLD="61.30"
HYBRID_NTRK_PT10_REFERENCE="6.42"           HYBRID_NTRK_PT10_THRESHOLD="6.66"
HYBRID_FAKE_REFERENCE="3.34"                HYBRID_FAKE_THRESHOLD="3.46"
HYBRID_DUP_REFERENCE="5.54"                 HYBRID_DUP_THRESHOLD="5.70"
HYBRID_Z0RES_LOWETA_REFERENCE="0.10"        HYBRID_Z0RES_LOWETA_THRESHOLD="0.110"
HYBRID_Z0RES_HIGHETA_REFERENCE="0.40"       HYBRID_Z0RES_HIGHETA_THRESHOLD="0.440"

# --- HYBRID_NEWKF (ttbar+PU200) ---
HYBRID_NEWKF_EFFI_ETA_LOW_REFERENCE="95.75"     HYBRID_NEWKF_EFFI_ETA_LOW_THRESHOLD="95.21"
HYBRID_NEWKF_EFFI_ETA_MID_REFERENCE="94.07"     HYBRID_NEWKF_EFFI_ETA_MID_THRESHOLD="93.20"
HYBRID_NEWKF_EFFI_ETA_HIGH_REFERENCE="95.94"    HYBRID_NEWKF_EFFI_ETA_HIGH_THRESHOLD="94.95"
HYBRID_NEWKF_EFFI_PT2_REFERENCE="95.29"         HYBRID_NEWKF_EFFI_PT2_THRESHOLD="94.87"
HYBRID_NEWKF_EFFI_PT2TO8_REFERENCE="95.27"      HYBRID_NEWKF_EFFI_PT2TO8_THRESHOLD="94.79"
HYBRID_NEWKF_EFFI_PT8_REFERENCE="95.35"         HYBRID_NEWKF_EFFI_PT8_THRESHOLD="94.51"
HYBRID_NEWKF_EFFI_PT40_REFERENCE="94.43"        HYBRID_NEWKF_EFFI_PT40_THRESHOLD="91.31"
HYBRID_NEWKF_TP_PT2_REFERENCE="157.01"          HYBRID_NEWKF_TP_PT2_THRESHOLD="155.82"
HYBRID_NEWKF_TP_PT3_REFERENCE="51.46"           HYBRID_NEWKF_TP_PT3_THRESHOLD="50.78"
HYBRID_NEWKF_TP_PT10_REFERENCE="4.73"           HYBRID_NEWKF_TP_PT10_THRESHOLD="4.52"
HYBRID_NEWKF_NTRK_PT2_REFERENCE="181.73"        HYBRID_NEWKF_NTRK_PT2_THRESHOLD="183.01"
HYBRID_NEWKF_NTRK_PT3_REFERENCE="65.04"         HYBRID_NEWKF_NTRK_PT3_THRESHOLD="65.80"
HYBRID_NEWKF_NTRK_PT10_REFERENCE="7.82"         HYBRID_NEWKF_NTRK_PT10_THRESHOLD="8.09"
HYBRID_NEWKF_FAKE_REFERENCE="6.05"              HYBRID_NEWKF_FAKE_THRESHOLD="6.21"
HYBRID_NEWKF_DUP_REFERENCE="6.82"               HYBRID_NEWKF_DUP_THRESHOLD="6.99"
HYBRID_NEWKF_Z0RES_LOWETA_REFERENCE="0.11"      HYBRID_NEWKF_Z0RES_LOWETA_THRESHOLD="0.121"
HYBRID_NEWKF_Z0RES_HIGHETA_REFERENCE="0.46"     HYBRID_NEWKF_Z0RES_HIGHETA_THRESHOLD="0.506"

# --- HYBRID_DISPLACED (displacedSUSY+PU200) ---
HYBRID_DISPLACED_EFFI_ETA_LOW_REFERENCE="95.63"     HYBRID_DISPLACED_EFFI_ETA_LOW_THRESHOLD="94.82"
HYBRID_DISPLACED_EFFI_ETA_MID_REFERENCE="95.02"     HYBRID_DISPLACED_EFFI_ETA_MID_THRESHOLD="93.94"
HYBRID_DISPLACED_EFFI_ETA_HIGH_REFERENCE="96.10"    HYBRID_DISPLACED_EFFI_ETA_HIGH_THRESHOLD="94.93"
HYBRID_DISPLACED_EFFI_PT2_REFERENCE="95.54"         HYBRID_DISPLACED_EFFI_PT2_THRESHOLD="94.97"
HYBRID_DISPLACED_EFFI_PT2TO8_REFERENCE="95.88"      HYBRID_DISPLACED_EFFI_PT2TO8_THRESHOLD="95.25"
HYBRID_DISPLACED_EFFI_PT8_REFERENCE="94.41"         HYBRID_DISPLACED_EFFI_PT8_THRESHOLD="93.09"
HYBRID_DISPLACED_EFFI_PT40_REFERENCE="89.53"        HYBRID_DISPLACED_EFFI_PT40_THRESHOLD="84.58"
HYBRID_DISPLACED_TP_PT2_REFERENCE="143.99"          HYBRID_DISPLACED_TP_PT2_THRESHOLD="142.85"
HYBRID_DISPLACED_TP_PT3_REFERENCE="42.80"           HYBRID_DISPLACED_TP_PT3_THRESHOLD="42.18"
HYBRID_DISPLACED_TP_PT10_REFERENCE="2.53"           HYBRID_DISPLACED_TP_PT10_THRESHOLD="2.38"
HYBRID_DISPLACED_NTRK_PT2_REFERENCE="292.48"        HYBRID_DISPLACED_NTRK_PT2_THRESHOLD="294.10"
HYBRID_DISPLACED_NTRK_PT3_REFERENCE="147.35"        HYBRID_DISPLACED_NTRK_PT3_THRESHOLD="148.50"
HYBRID_DISPLACED_NTRK_PT10_REFERENCE="39.72"        HYBRID_DISPLACED_NTRK_PT10_THRESHOLD="40.32"
HYBRID_DISPLACED_FAKE_REFERENCE="39.20"             HYBRID_DISPLACED_FAKE_THRESHOLD="39.46"
HYBRID_DISPLACED_DUP_REFERENCE="5.17"               HYBRID_DISPLACED_DUP_THRESHOLD="5.29"
HYBRID_DISPLACED_Z0RES_LOWETA_REFERENCE="0.11"      HYBRID_DISPLACED_Z0RES_LOWETA_THRESHOLD="0.121"
HYBRID_DISPLACED_Z0RES_HIGHETA_REFERENCE="0.42"     HYBRID_DISPLACED_Z0RES_HIGHETA_THRESHOLD="0.462"

# =============================================================================
# SANITY CHECK
# =============================================================================
if [ -z "$CMSSW_BASE" ]; then
    echo "ERROR: CMSSW_BASE is not set. Run cmsenv before this script."
    exit 1
fi

# =============================================================================
# STAGE 1: Compile + Run
# Compiles all checked out packages, then streams the appropriate MC dataset
# directly and runs cmsRun for each algorithm.
# =============================================================================
echo ""
echo "=== STAGE 1: Compile + Run ==="

echo "--- Compiling ---"
cd $CMSSW_BASE/src
scram b -j
echo "--- Compile: SUCCESS ---"

run_hybrid_stage() {
    local ALGO=$1
    local RESULTS_LABEL=$2

    # HYBRID_DISPLACED runs on displacedSUSY+PU200; everything else (prompt
    # tracking) runs on ttbar+PU200.
    local DATASET DESCRIPTION
    if [[ "$ALGO" = *"DISPLACED"* ]]; then
        DATASET="$MC_DATASET_DISPLACED"
        DESCRIPTION="$MC_DESCRIPTION_DISPLACED"
    else
        DATASET="$MC_DATASET_PROMPT"
        DESCRIPTION="$MC_DESCRIPTION_PROMPT"
    fi

    echo ""
    echo "--- Running algo=$ALGO ---"
    echo "    MC = $DATASET"
    echo "         $DESCRIPTION"

    if [ ! -d "$TEST_DIR" ]; then
        echo "ERROR: Test directory not found at $TEST_DIR"
        exit 1
    fi

    cd $TEST_DIR

    JOBNAME="job_${ALGO}_${RESULTS_LABEL}_cfg.py"
    cp $CFG_FILE $JOBNAME
    sed -i "s|L1TRKALGO = 'HYBRID'|L1TRKALGO = '$ALGO'|" $JOBNAME
    grep "^L1TRKALGO" $JOBNAME

    RESULTSDIR="$TEST_DIR/unit_test_results/${ALGO}_${RESULTS_LABEL}"
    rm -rf $RESULTSDIR
    mkdir -p $RESULTSDIR

    echo "process.TFileService.fileName = cms.string('$RESULTSDIR/histos.root')" >> $JOBNAME
    echo "process.maxEvents = cms.untracked.PSet(input = cms.untracked.int32($EVENTS))" >> $JOBNAME
    echo "process.options.numberOfThreads = cms.untracked.uint32($JOBS)" >> $JOBNAME
    echo "process.options.numberOfStreams = cms.untracked.uint32(0)" >> $JOBNAME
    # Stream the dataset directly
    echo "process.source.fileNames = cms.untracked.vstring('$DATASET')" >> $JOBNAME

    echo "--- Running cmsRun ---"
    cmsRun $JOBNAME
    echo "--- cmsRun: SUCCESS ---"
    rm $JOBNAME
}

run_hybrid_stage HYBRID "run"

if [ "$QUICK_TEST" = "false" ]; then
    run_hybrid_stage HYBRID_NEWKF     "run"
    run_hybrid_stage HYBRID_DISPLACED "run"
fi

echo ""
echo "=== STAGE 1: SUCCESS ==="

# =============================================================================
# STAGE 2: Analysis
# Runs makeHists.csh on each algorithm's output ROOT file to produce
# results.out, then validates physics output against reference thresholds.
# =============================================================================
echo ""
echo "=== STAGE 2: Analysis ==="

run_makehists() {
    local ALGO=$1
    local RESULTS_LABEL=$2
    local RESULTSDIR="$TEST_DIR/unit_test_results/${ALGO}_${RESULTS_LABEL}"

    echo ""
    echo "--- Running makeHists.csh for algo=$ALGO ---"
    cd $RESULTSDIR
    tcsh $TEST_DIR/makeHists.csh histos.root

    if [ ! -f "results.out" ]; then
        echo "FAILURE - results.out not produced for $ALGO"
        exit 1
    fi
    echo "--- makeHists.csh: SUCCESS ---"
    cd $TEST_DIR
}

run_makehists HYBRID "run"
if [ "$QUICK_TEST" = "false" ]; then
    run_makehists HYBRID_NEWKF     "run"
    run_makehists HYBRID_DISPLACED "run"
fi

check_threshold() {
    local ALGO=$1
    local LABEL=$2
    local GREP_STRING=$3
    local THRESHOLD=$4
    local MODE=$5
    local METRIC_NAME=$6

    local RESULTSFILE="$TEST_DIR/unit_test_results/${ALGO}_${LABEL}/results.out"

    if [ ! -f "$RESULTSFILE" ]; then
        echo "FAILURE -- $RESULTSFILE not found"
        return 1
    fi

    local VALUE=$(grep "$GREP_STRING" "$RESULTSFILE" | head -1 | cut -f2 -d= | cut -f1 -d+ | tr -d ' ' | tr -d 'cm' | cut -f1 -d'%' | cut -f1 -d' ' | sed 's/at.*//')

    if [ -z "$VALUE" ]; then
        echo "FAILURE -- could not find '$GREP_STRING' in $RESULTSFILE"
        return 1
    fi

    # Guard against a malformed/non-numeric VALUE silently passing bc.
    if ! [[ "$VALUE" =~ ^-?[0-9]+([.][0-9]+)?$ ]]; then
        echo "FAILURE -- parsed value '$VALUE' for '$GREP_STRING' is not numeric"
        return 1
    fi

    local FAIL
    local THRESHOLD_LABEL
    if [ "$MODE" = "min" ]; then
        FAIL=$(echo "$VALUE < $THRESHOLD" | bc)
        THRESHOLD_LABEL="Threshold Minimum: $THRESHOLD"
    else
        FAIL=$(echo "$VALUE > $THRESHOLD" | bc)
        THRESHOLD_LABEL="Threshold Maximum: $THRESHOLD"
    fi

    if (( $FAIL )); then
        echo "FAILURE -- [$ALGO/$LABEL] $METRIC_NAME = $VALUE ($THRESHOLD_LABEL)"
        return 1
    else
        echo "SUCCESS -- [$ALGO/$LABEL] $METRIC_NAME = $VALUE ($THRESHOLD_LABEL)"
        return 0
    fi
}

OVERALL_FAIL=0
run_all_checks() {
    local ALGO=$1
    local LABEL=$2
    local PREFIX="${ALGO}"

    check_threshold "$ALGO" "$LABEL" "efficiency for |eta| < 1.0"         "$(eval echo \$${PREFIX}_EFFI_ETA_LOW_THRESHOLD)"  "min" "effi |eta|<1.0"      || OVERALL_FAIL=1
    check_threshold "$ALGO" "$LABEL" "efficiency for 1.0 < |eta| < 1.75"  "$(eval echo \$${PREFIX}_EFFI_ETA_MID_THRESHOLD)"  "min" "effi 1.0<|eta|<1.75" || OVERALL_FAIL=1
    check_threshold "$ALGO" "$LABEL" "efficiency for 1.75 < |eta| < 2.50" "$(eval echo \$${PREFIX}_EFFI_ETA_HIGH_THRESHOLD)" "min" "effi 1.75<|eta|<2.50" || OVERALL_FAIL=1
    check_threshold "$ALGO" "$LABEL" "efficiency for pt > 2.00"            "$(eval echo \$${PREFIX}_EFFI_PT2_THRESHOLD)"      "min" "effi pt>2.00"         || OVERALL_FAIL=1
    check_threshold "$ALGO" "$LABEL" "efficiency for 2.00 < pt < 8.0"     "$(eval echo \$${PREFIX}_EFFI_PT2TO8_THRESHOLD)"   "min" "effi 2.00<pt<8.0"    || OVERALL_FAIL=1
    check_threshold "$ALGO" "$LABEL" "efficiency for pt > 8.0"             "$(eval echo \$${PREFIX}_EFFI_PT8_THRESHOLD)"      "min" "effi pt>8.0"          || OVERALL_FAIL=1
    check_threshold "$ALGO" "$LABEL" "efficiency for pt > 40.0"            "$(eval echo \$${PREFIX}_EFFI_PT40_THRESHOLD)"     "min" "effi pt>40.0"         || OVERALL_FAIL=1
    check_threshold "$ALGO" "$LABEL" "TP/event (pt > 2.00)"                "$(eval echo \$${PREFIX}_TP_PT2_THRESHOLD)"        "min" "TP/event pt>2.00"     || OVERALL_FAIL=1
    check_threshold "$ALGO" "$LABEL" "TP/event (pt > 3.0)"                 "$(eval echo \$${PREFIX}_TP_PT3_THRESHOLD)"        "min" "TP/event pt>3.0"      || OVERALL_FAIL=1
    check_threshold "$ALGO" "$LABEL" "TP/event (pt > 10.0)"                "$(eval echo \$${PREFIX}_TP_PT10_THRESHOLD)"       "min" "TP/event pt>10.0"     || OVERALL_FAIL=1
    check_threshold "$ALGO" "$LABEL" "tracks/event (pt > 2.00)"            "$(eval echo \$${PREFIX}_NTRK_PT2_THRESHOLD)"      "max" "tracks/event pt>2.00" || OVERALL_FAIL=1
    check_threshold "$ALGO" "$LABEL" "tracks/event (pt > 3.0)"             "$(eval echo \$${PREFIX}_NTRK_PT3_THRESHOLD)"      "max" "tracks/event pt>3.0"  || OVERALL_FAIL=1
    check_threshold "$ALGO" "$LABEL" "tracks/event (pt > 10.0)"            "$(eval echo \$${PREFIX}_NTRK_PT10_THRESHOLD)"     "max" "tracks/event pt>10.0" || OVERALL_FAIL=1
    check_threshold "$ALGO" "$LABEL" "Percentage fake tracks"               "$(eval echo \$${PREFIX}_FAKE_THRESHOLD)"          "max" "fake tracks %"        || OVERALL_FAIL=1
    check_threshold "$ALGO" "$LABEL" "Percentage duplicate tracks"          "$(eval echo \$${PREFIX}_DUP_THRESHOLD)"           "max" "duplicate tracks %"   || OVERALL_FAIL=1
    check_threshold "$ALGO" "$LABEL" "z0 resolution = .*0.05"              "$(eval echo \$${PREFIX}_Z0RES_LOWETA_THRESHOLD)"  "max" "z0 res |eta|=0.05"    || OVERALL_FAIL=1
    check_threshold "$ALGO" "$LABEL" "z0 resolution = .*1.95"              "$(eval echo \$${PREFIX}_Z0RES_HIGHETA_THRESHOLD)" "max" "z0 res |eta|=1.95"    || OVERALL_FAIL=1
}
#We only run threshold checks for 1000+ events as thresholds are from 1000 event run
#and could silently pass a bad PR with lower events due to higher statistal uncertainty.
#The case isn't true for >1000 though as it would hone in more precisely not on a "better" value.
echo ""
if [ "$EVENTS" -ge 1000 ]; then
    echo "--- Validating thresholds (EVENTS=$EVENTS) ---"
    run_all_checks HYBRID run
    if [ "$QUICK_TEST" = "false" ]; then
        run_all_checks HYBRID_NEWKF     run
        run_all_checks HYBRID_DISPLACED run
    fi

    echo ""
    if (( $OVERALL_FAIL )); then
        echo "=== STAGE 2: FAILURE -- one or more thresholds not met ==="
        echo "=== OVERALL RESULT: FAILURE ==="
        exit 1
    else
        echo "=== STAGE 2: SUCCESS - all thresholds passed ==="
        echo "=== OVERALL RESULT: SUCCESS ==="
    fi
else
    echo "--- Skipping threshold validation: EVENTS=$EVENTS is below the 1000-event reference count thresholds were calibrated for ---"
fi