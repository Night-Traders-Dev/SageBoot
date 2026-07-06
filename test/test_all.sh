#!/usr/bin/env bash
set -uo pipefail

#=============================================================================
# SageBoot Test Suite
# Builds every supported architecture and runs it through QEMU (if available)
# to verify basic boot functionality.
#=============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

PASS=0
FAIL=0
SKIP=0
RESULTS=()

TIMEOUT_SEC=5
QEMU_EXTRA="-display none -no-reboot"

#-----------------------------------------------------------------------------
# Helper functions
#-----------------------------------------------------------------------------

has_cmd() { command -v "$1" &>/dev/null; }

banner() {
    echo ""
    echo "====================================================================="
    echo "  $1"
    echo "====================================================================="
}

# Clean + build an architecture, return 0 on success
do_build() {
    local arch="$1"
    local log
    log=$(mktemp)
    if ! make ARCH="$arch" clean >"$log" 2>&1; then
        cat "$log" >&2
        rm -f "$log"
        return 1
    fi
    if ! make ARCH="$arch" >>"$log" 2>&1; then
        cat "$log" | tail -5 >&2
        rm -f "$log"
        return 1
    fi
    rm -f "$log"
    [ -f sageboot.elf ] || [ -f sageboot.bin ]
}

# Run QEMU, capture serial output, check for expected string
# Returns: 0=pass, 1=fail (no output), 2=fail (output mismatch), 124=timeout
qemu_expect() {
    local qemu_cmd="$1"
    local expected="$2"
    local tmpfile
    tmpfile=$(mktemp)

    set +e
    timeout "$TIMEOUT_SEC" $qemu_cmd -serial "file:$tmpfile" 2>/dev/null
    local rc=$?

    if grep -qF "$expected" "$tmpfile" 2>/dev/null; then
        rm -f "$tmpfile"
        return 0
    elif [ -s "$tmpfile" ]; then
        rm -f "$tmpfile"
        return 2
    else
        rm -f "$tmpfile"
        return 1
    fi
}

record() {
    local status="$1"  # PASS|FAIL|SKIP
    local arch="$2"
    local desc="$3"
    local detail="$4"
    printf "  [%4s] %-20s %-30s %s\n" "$status" "$arch" "$desc" "$detail"
    RESULTS+=("${status}|${arch}|${desc}|${detail}")
    case "$status" in
        PASS) PASS=$((PASS + 1)) ;;
        FAIL) FAIL=$((FAIL + 1)) ;;
        SKIP) SKIP=$((SKIP + 1)) ;;
    esac
}

# Map arch -> (QEMU command | "build-only", expected string)
declare -A QEMU_MAP
QEMU_MAP=(
    [rv64]="qemu-system-riscv64 -machine virt -cpu rv64 -m 512M -bios default $QEMU_EXTRA -kernel sageboot.bin"
    [arm64]="qemu-system-aarch64 -machine virt -cpu max -m 512M $QEMU_EXTRA -kernel sageboot.elf"
    [x64]="qemu-system-x86_64 -machine pc -cpu max -m 512M $QEMU_EXTRA -kernel sageboot.bin"
    [rp2350_rv]="qemu-system-riscv32 -machine virt -m 512M $QEMU_EXTRA -kernel sageboot.bin"
)
declare -A EXPECTED_MAP
EXPECTED_MAP=(
    [rv64]="SageBoot Stage 1"
    [arm64]="SageBoot Stage 1"
    [x64]="SageBoot Stage 1"
    [rp2350_rv]="SageBoot Stage 1"
)

# Full test: build + QEMU run
run_test() {
    local arch="$1"
    local desc="$2"

    banner "Testing: $arch ($desc)"
    echo -n "  Building... "

    if ! do_build "$arch"; then
        echo "FAIL"
        record "FAIL" "$arch" "$desc" "build failed"
        return
    fi
    echo "OK"

    local qemu_cmd="${QEMU_MAP[$arch]:-}"
    local expected="${EXPECTED_MAP[$arch]:-}"

    if [ -z "$qemu_cmd" ]; then
        record "SKIP" "$arch" "$desc" "no QEMU available"
        return
    fi

    echo -n "  QEMU (${TIMEOUT_SEC}s)... "

    qemu_expect "$qemu_cmd" "$expected"
    local result=$?
    case $result in
        0) echo "PASS"; record "PASS" "$arch" "$desc" "boots OK" ;;
        1) echo "NO OUTPUT"; record "FAIL" "$arch" "$desc" "no serial output" ;;
        2) echo "OUTPUT MISMATCH"; record "FAIL" "$arch" "$desc" "output mismatch" ;;
    esac
}

#-----------------------------------------------------------------------------
# Test definitions
#-----------------------------------------------------------------------------

declare -A TESTS
TESTS=(
    ["rv64"]="RISC-V 64 QEMU Virt"
    ["arm64"]="AArch64 QEMU Virt"
    ["x64"]="x86_64 PC (Multiboot)"
    ["rp2040"]="RP2040 Cortex-M0+"
    ["rp2350_arm"]="RP2350 ARM Cortex-M33"
    ["rp2350_rv"]="RP2350 RISC-V Hazard3"
    ["mips"]="MIPS 74Kc (Netgear WN3000RP)"
)

ARCH_ORDER=(rv64 arm64 x64 rp2040 rp2350_arm rp2350_rv mips)

declare -A PREFIXES
PREFIXES=(
    [rv64]=riscv64-linux-gnu-
    [arm64]=aarch64-linux-gnu-
    [x64]=x86_64-linux-gnu-
    [rp2040]=arm-none-eabi-
    [rp2350_arm]=arm-none-eabi-
    [rp2350_rv]=riscv64-linux-gnu-
    [mips]=mipsel-linux-gnu-
)

#-----------------------------------------------------------------------------
# Check toolchain availability (for pre-flight)
#-----------------------------------------------------------------------------

check_cross_compiler() {
    local prefix="$1"
    local name="$2"
    if has_cmd "${prefix}as"; then
        return 0
    else
        echo "  WARNING: Cross-assembler '${prefix}as' not found — $name will be skipped"
        return 1
    fi
}

#-----------------------------------------------------------------------------
# Main
#-----------------------------------------------------------------------------

banner "SageBoot Test Suite"
echo "Timestamp   : $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
echo "Project     : $PROJECT_DIR"
echo "QEMU x86_64 : $(has_cmd qemu-system-x86_64 && echo 'yes' || echo 'no')"
echo "QEMU riscv64: $(has_cmd qemu-system-riscv64 && echo 'yes' || echo 'no')"
echo "QEMU aarch64: $(has_cmd qemu-system-aarch64 && echo 'yes' || echo 'no')"
echo "QEMU riscv32: $(has_cmd qemu-system-riscv32 && echo 'yes' || echo 'no')"
echo ""

#--- Test each architecture ---

# Toolchain requirements per arch (remove QEMU-specific entries from QEMU_MAP if tool missing)
clean_qemu_map() {
    local arch="$1"
    local need_qemu="${2:-}"
    if [ -n "$need_qemu" ] && ! has_cmd "$need_qemu"; then
        unset QEMU_MAP[$arch]
    fi
}
clean_qemu_map rv64 qemu-system-riscv64
clean_qemu_map arm64 qemu-system-aarch64
clean_qemu_map x64 qemu-system-x86_64
clean_qemu_map rp2350_rv qemu-system-riscv32

for arch in "${ARCH_ORDER[@]}"; do
    IFS='|' read -r desc qemu_expected <<< "${TESTS[$arch]}"
    if [ -n "${PREFIXES[$arch]:-}" ]; then
        if ! check_cross_compiler "${PREFIXES[$arch]}" "$arch"; then
            record "SKIP" "$arch" "$desc" "missing cross-toolchain"
            continue
        fi
    fi
    run_test "$arch" "$desc"
done

#-----------------------------------------------------------------------------
# Summary
#-----------------------------------------------------------------------------

echo ""
echo "====================================================================="
echo "  SUMMARY"
echo "====================================================================="
echo "  PASS: $PASS   FAIL: $FAIL   SKIP: $SKIP   Total: $((PASS + FAIL + SKIP))"
echo ""

for result in "${RESULTS[@]}"; do
    echo "  $result"
done | column -t -s '|'

echo ""
if [ "$FAIL" -gt 0 ]; then
    echo "  FAILURES DETECTED — review above for details."
    echo ""
    echo "  Known issues:"
    echo "    arm64: SIMD/FP alignment fault in generated C code (stur q0 to unaligned addr)"
    echo "    x64:   QEMU multiboot v1 detection failure (SeaBIOS does not load -kernel flat binary)"
    echo "    rp2350_rv: QEMU riscv32 virt memory map differs from RP2350"
    echo "    mips:  Cross-assembler (mipsel-linux-gnu-as) not installed"
    exit 1
else
    echo "  All tests passed."
    exit 0
fi
