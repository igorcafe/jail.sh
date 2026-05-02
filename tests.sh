#!/usr/bin/env bash

set -u

green=$'\033[1;32m'
red=$'\033[1;31m'
bold=$'\033[1m'
white=$'\033[1;37m'
reset=$'\033[0m'
status=0

jdescribe () {
    printf '\n%s%s%s\n' "$white" "$1" "$reset" >&2
}

jtest () {
    command="$1"
    display_command="$command"

    if [[ "$command" == '! '* ]]
    then
        display_command="${red}!${reset} ${command#! }"
    fi

    if output="$(eval "$command" 2>&1)"
    then
        printf '%sPASS%s: %b\n' "$green" "$reset" "$display_command" >&2
    else
        printf '%sFAIL%s: %b\n' "$red" "$reset" "$display_command" >&2
        echo "$output" >&2
	      status=1
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

jdescribe 'builtin sh'
jtest './jail -- bash -c "echo exit | sh"'

jdescribe 'extra programs'
jtest './jail -p printf -- sh -c "printf ok"'

jdescribe 'working directory bind shortcut'
jtest './jail --wd /tmp -- sh -c "test \"\$PWD\" = /tmp"'
jtest '! ./jail --wd tmp -- true'
jtest '! ./jail --wd /tmp --share-wd ro -- true'
jtest './jail --share-wd ro -- ls "$PWD"'
jtest '! ./jail --share-wd ro -- touch "$PWD"'
jtest './jail --share-wd rw -- ls "$PWD"'
jtest './jail --share-wd rw -- touch "$PWD"'
jtest '! ./jail --share-wd bad -- true'

jdescribe 'environment'
jtest './jail -e FOO=bar -- sh -c "test \"\$FOO\" = bar"'
jtest './jail --home /tmp -- sh -c "test \"\$HOME\" = /tmp"'
jtest './jail --share-home ro -- sh -c "test \"\$HOME\" = \"$HOME\""'
jtest './jail --share-home ro -- ls "$HOME"'
jtest '! ./jail --share-home ro -- touch "$HOME/.jail-test-share-home"'
jtest './jail --share-home rw -- touch "$HOME/.jail-test-share-home"'
jtest '! ./jail --home /tmp --share-home ro -- true'
rm -f "$HOME/.jail-test-share-home"

jdescribe 'custom binds'
rm -f .jail-test-touch
jtest './jail -b "$PWD:$PWD:ro" -- ls "$PWD"'
jtest '! ./jail -b "$PWD:$PWD:ro" -- touch "$PWD/.jail-test-touch"'
jtest './jail -b "$PWD:$PWD:rw" -- ls "$PWD"'
jtest './jail -b "$PWD:$PWD:rw" -- touch "$PWD/.jail-test-touch"'
jtest '! ./jail -b "$PWD:$PWD" -- true'
rm -f .jail-test-touch

exit $status
