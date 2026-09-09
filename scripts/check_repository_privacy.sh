#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
FAILURES=0

pass() { print "[PASS] $1" }
fail() {
    print "[FAIL] $1"
    FAILURES=$((FAILURES + 1))
}

cd "$PROJECT_ROOT"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    fail "Repository privacy check must run inside a Git worktree"
else
    risky_files=$(git ls-files | grep -E -i '(^|/)(taskdeck\.sqlite3?(-wal|-shm)?|tasks\.json|focus-sessions\.json|focus-runtime\.json|release\.env|privacy_denylist\.txt)$|(^|/)xcuserdata/|\.(p12|cer|mobileprovision|provisionprofile|dmg)$' || true)
    if [[ -n "$risky_files" ]]; then
        print -r -- "$risky_files"
        fail "High-risk local data or signing files are tracked"
    else
        pass "No local databases, task JSON, credentials, or signing files are tracked"
    fi

    secret_findings=$(git grep -n -I -E 'BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY|github_pat_[A-Za-z0-9_]+|gh[pousr]_[A-Za-z0-9_]{20,}|AKIA[0-9A-Z]{16}' -- . ':!scripts/check_repository_privacy.sh' || true)
    if [[ -n "$secret_findings" ]]; then
        print -r -- "$secret_findings"
        fail "A credential-like value is present in tracked text"
    else
        pass "No common private-key or access-token pattern is present"
    fi

    email_findings=$(git grep -n -I -E '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' -- . ':!scripts/check_release_privacy.sh' ':!scripts/privacy_denylist.txt.example' ':!scripts/check_repository_privacy.sh' | grep -v -E 'icon_[A-Za-z0-9_]+@2x\.png' || true)
    if [[ -n "$email_findings" ]]; then
        print -r -- "$email_findings"
        fail "An email address is present in tracked project text"
    else
        pass "No email address is present in tracked project text"
    fi

    path_findings=$(git grep -n -I -E '/Users/[A-Za-z0-9._-]+/' -- . ':!scripts/check_release_privacy.sh' ':!scripts/check_repository_privacy.sh' || true)
    if [[ -n "$path_findings" ]]; then
        print -r -- "$path_findings"
        fail "An absolute macOS home-directory path is present in tracked text"
    else
        pass "No absolute macOS home-directory path is present in tracked text"
    fi
fi

if (( FAILURES > 0 )); then
    print "Repository privacy check failed with $FAILURES issue(s)."
    exit 1
fi

print "Repository privacy check passed."
