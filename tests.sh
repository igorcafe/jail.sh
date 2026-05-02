#!/usr/bin/env bash

set -eu

green=$'\033[1;32m'
red=$'\033[1;31m'
bold=$'\033[1m'
white=$'\033[1;37m'
reset=$'\033[0m'

jdescribe () {
    printf '\n%s%s%s\n' "$white" "$1" "$reset" >&2
}

jtest () {
    command="$1"
    if output="$(eval "$command" 2>&1)"
    then
        printf '%sPASS%s: %s\n' "$green" "$reset" "$command" >&2
    else
        printf '%sFAIL%s: %s\n' "$red" "$reset" "$command" >&2
        echo "$output" >&2
        return 1
    fi
}

jdescribe 'command separator'
jtest './jail -- ls'
jtest '! ./jail -- ls "$HOME"'

jdescribe 'usage and command validation'
jtest '! ./jail'
jtest '! ./jail ls'
jtest '! ./jail --'

jdescribe 'extra programs'
jtest './jail -p printf -- sh -c "printf ok"'
jtest './jail --programs printf -- sh -c "printf ok"'

jdescribe 'working directory bind shortcut'
jtest './jail --wd ro -- ls "$PWD"'
jtest './jail --wd rw -- ls "$PWD"'
jtest '! ./jail --wd bad -- true'

jdescribe 'environment'
jtest './jail -e FOO=bar -- sh -c "test \"\$FOO\" = bar"'
jtest './jail --home /tmp -- sh -c "test \"\$HOME\" = /tmp"'

jdescribe 'custom binds'
rm -f .jail-test-touch
jtest './jail -b "$PWD:$PWD:ro" -- ls "$PWD"'
jtest '! ./jail -b "$PWD:$PWD:ro" -- touch "$PWD/.jail-test-touch"'
jtest './jail --bind "$PWD:$PWD:rw" -- ls "$PWD"'
jtest './jail --bind "$PWD:$PWD:rw" -- touch "$PWD/.jail-test-touch"'
jtest '! ./jail -b "$PWD:$PWD" -- true'
rm -f .jail-test-touch
