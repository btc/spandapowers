#!/usr/bin/env bash
# Run all skill triggering tests
# Usage: ./run-all.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROMPTS_DIR="$SCRIPT_DIR/prompts"

SKILLS=(
    "burndown-reviews"
    "systematic-debugging"
    "test-driven-development"
    "writing-plans"
    "dispatching-parallel-agents"
    "executing-plans"
    "requesting-code-review"
)

echo "=== Running Skill Triggering Tests ==="
echo ""

PASSED=0
FAILED=0
RESULTS=()

# Per-test setup
# Sets MAX_TURNS and performs any fixture setup needed for the skill.
MAX_TURNS=3
case_setup() {
    MAX_TURNS=3
    case "$1" in
        burndown-reviews)
            MAX_TURNS=7
            cat > /tmp/burndown-test-spec.md <<'EOF'
# Test Spec for Burndown-Reviews Triggering

## Motivation
A minimal stub spec for the skill-triggering test fixture.
EOF
            ;;
    esac
}

for skill in "${SKILLS[@]}"; do
    prompt_file="$PROMPTS_DIR/${skill}.txt"

    if [ ! -f "$prompt_file" ]; then
        echo "⚠️  SKIP: No prompt file for $skill"
        continue
    fi

    echo "Testing: $skill"
    case_setup "$skill"

    if "$SCRIPT_DIR/run-test.sh" "$skill" "$prompt_file" "$MAX_TURNS" 2>&1 | tee /tmp/skill-test-$skill.log; then
        PASSED=$((PASSED + 1))
        RESULTS+=("✅ $skill")
    else
        FAILED=$((FAILED + 1))
        RESULTS+=("❌ $skill")
    fi

    echo ""
    echo "---"
    echo ""
done

echo ""
echo "=== Summary ==="
for result in "${RESULTS[@]}"; do
    echo "  $result"
done
echo ""
echo "Passed: $PASSED"
echo "Failed: $FAILED"

if [ $FAILED -gt 0 ]; then
    exit 1
fi
