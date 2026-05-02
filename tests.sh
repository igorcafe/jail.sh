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
jtest './jail -- sh -c "test \"\$PWD\" = /"'

jdescribe 'incorrect usage'
jtest '! ./jail'
jtest '! ./jail ls'
jtest '! ./jail --'

jdescribe 'builtin sh'
jtest './jail -- bash -c "echo exit | sh"'

jdescribe 'extra programs'
jtest './jail -p printf -- sh -c "printf ok"'
jtest './jail -p printf -p cat -- sh -c "printf ok | test \"\$(cat)\" = ok"'
jtest '! ./jail -p printf,cat -- true'

jdescribe 'devices'
jtest './jail -- sh -c "test -e /dev/null"'
jtest './jail -- sh -c "test -e /dev/zero"'
jtest './jail -- sh -c "test -e /dev/random"'
jtest './jail -- sh -c "test -e /dev/urandom"'
jtest './jail -- sh -c "test -e /dev/tty"'
jtest './jail -d null -- sh -c "test -e /dev/null"'
jtest './jail -d null -d null -- sh -c "test -e /dev/null"'
if command -v script > /dev/null
then
    jtest "script -qefc './jail -- sh -c \"test -t 0 && : < /dev/tty\"' /dev/null"
    jtest "script -qefc 'before=\$(stty -g); ./jail -- stty raw -echo; test \"\$(stty -g)\" = \"\$before\"' /dev/null"
fi
jtest '! ./jail -d /dev/null -- true'
jtest '! ./jail -d ../null -- true'
jtest '! ./jail -d jail-does-not-exist -- true'

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
jtest './jail -E HOME -- sh -c "test \"\$HOME\" = \"$HOME\""'
jtest '! ./jail -E JAIL_TEST_ENV_DOES_NOT_EXIST -- true'
jtest '! ./jail -E 1BAD -- true'
jtest './jail --home /tmp -- sh -c "test \"\$HOME\" = /tmp"'
jtest './jail --home /tmp -- sh -c "test \"\$PWD\" = /tmp"'
jtest './jail --home /tmp --wd / -- sh -c "test \"\$PWD\" = /"'
jtest './jail --share-home ro -- sh -c "test \"\$HOME\" = \"$HOME\""'
jtest './jail --share-home ro -- sh -c "test \"\$PWD\" = \"\$HOME\""'
jtest './jail --share-home ro --wd /tmp -- sh -c "test \"\$PWD\" = /tmp"'
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
jtest './jail -B "$PWD:ro" -- ls "$PWD"'
jtest '! ./jail -B "$PWD:ro" -- touch "$PWD/.jail-test-touch"'
jtest './jail -B "$PWD:rw" -- touch "$PWD/.jail-test-touch"'
jtest '! ./jail -B "$PWD" -- true'
jtest '! ./jail -B "$PWD:bad" -- true'
rm -f .jail-test-touch

exit $status
