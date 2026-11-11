# Shared helpers for tests/*.sh; tests/run sources this first.
#   check "what it shows" command...   passes if the command succeeds (and
#                                      returns non-zero if it doesn't)
#   skip "why"                         skips the rest of this file
#   box command...                     runs a command on the Apple TV
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
        return 1
    fi
}

# The Apple TV, for tests that run with TEST_BOX=1 (TEST_HOST overrides it).
# An unreachable box fails in ~10 s and one that stops answering in ~15 s,
# instead of ssh waiting minutes for TCP to give up.
BOX_HOST=${TEST_HOST:-apple@applereplay.local}
box() {
    ssh -i "$PROJECT/out/ssh/totalreplay_ed25519" -o BatchMode=yes -o ConnectTimeout=10 \
        -o ServerAliveInterval=5 -o ServerAliveCountMax=3 "$BOX_HOST" "$@"
}

skip() {
    echo "  skip  $*"
    exit 0
}

finish() {
    [ "$failed" -eq 0 ]
}
