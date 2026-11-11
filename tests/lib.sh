# Shared helpers for tests/*.sh; tests/run sources this first.
#   check "what it shows" command...   passes if the command succeeds
#   skip "why"                         skips the rest of this file
PROJECT=$(cd "$TESTS/.." && pwd)
SCRATCH=$PROJECT/out/test
passed=0
failed=0

check() {
    what=$1
    shift
    if "$@" >"$SCRATCH/last.log" 2>&1; then
        echo "  ok    $what"
        passed=$((passed + 1))
    else
        echo "  FAIL  $what"
        sed 's/^/        /' "$SCRATCH/last.log" | tail -15
        failed=$((failed + 1))
    fi
}

skip() {
    echo "  skip  $*"
    exit 0
}

finish() {
    [ "$failed" -eq 0 ]
}
