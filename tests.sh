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
jtest './jail -- pwd'
jtest './jail -- ls'
jtest './jail -- ls "/home/${USER:-user}"'
jtest './jail -- sh -c "test -d \"\$PWD\""'
jtest './jail -B "${PWD}:ro" -e "EXPECTED_PWD=${PWD}" -- sh -c "test \"\$PWD\" = \"\$EXPECTED_PWD\""'

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

jdescribe 'coreutils'
jtest './jail --core -- sh -c "test \$(printf ok | wc -c) -eq 2"'
jtest './jail --core -- sh -c "command -v ls && command -v cp && command -v sort"'

jdescribe 'devices'
jtest './jail -- sh -c "test -e /dev/null"'
jtest './jail -- sh -c "test -e /dev/zero"'
jtest './jail -- sh -c "test -e /dev/random"'
jtest './jail -- sh -c "test -e /dev/urandom"'
jtest './jail -- sh -c "test -e /dev/tty"'
jtest './jail -- sh -c "test -d /dev/shm && : > /dev/shm/jail-test-shm"'
jtest './jail -- sh -c "test -e /dev/fd/0 && test -e /dev/stdin && test -e /dev/stdout && test -e /dev/stderr"'
jtest './jail -d null -- sh -c "test -e /dev/null"'
jtest './jail -d null -d null -- sh -c "test -e /dev/null"'
jtest "script -qefc './jail -- sh -c \"test -t 0 && : < /dev/tty\"' /dev/null"
jtest "script -qefc 'before=\$(stty -g); ./jail -- stty raw -echo; test \"\$(stty -g)\" = \"\$before\"' /dev/null"
jtest '! ./jail -d /dev/null -- true'
jtest '! ./jail -d ../null -- true'
jtest '! ./jail -d jail-does-not-exist -- true'
jtest './jail -d! jail-does-not-exist -- true'
jtest '! ./jail -d! ../null -- true'
jtest './jail --gui -- sh -c "test -e /dev/snd && test -e /dev/dri && test \"\$XDG_RUNTIME_DIR\" = \"$XDG_RUNTIME_DIR\""'
if [[ -e /sys/class/input && -e /run/udev ]]
then
    jtest './jail --gui -- sh -c "test -e /sys/class/input && test -e /run/udev"'
fi
if [[ -e /dev/input ]]
then
    jtest './jail --gui -- sh -c "test -e /dev/input"'
fi

jdescribe 'network'
host_net_namespace="$(readlink /proc/self/ns/net)"
jtest '! ./jail -p readlink -e "HOST_NET_NAMESPACE=$host_net_namespace" -- sh -c "test \"\$(readlink /proc/self/ns/net)\" = \"\$HOST_NET_NAMESPACE\""'
jtest './jail --net -p readlink -e "HOST_NET_NAMESPACE=$host_net_namespace" -- sh -c "test \"\$(readlink /proc/self/ns/net)\" = \"\$HOST_NET_NAMESPACE\""'
jtest './jail --net -- sh -c "test ! -e /etc/resolv.conf || test -r /etc/resolv.conf"'
jtest './jail --net -- sh -c "test ! -e /etc/ssl/certs/ca-certificates.crt || test -r /etc/ssl/certs/ca-certificates.crt"'

jdescribe 'working directory bind shortcut'
jtest './jail --wd /tmp -- sh -c "test \"\$PWD\" = /tmp"'
jtest '! ./jail --wd tmp -- true'
jtest '! ./jail --wd /tmp --share-wd ro -- true'
jtest './jail --share-wd ro -e "EXPECTED_PWD=$PWD" -- sh -c "test \"\$PWD\" = \"\$EXPECTED_PWD\""'
jtest './jail --share-wd ro -- ls "$PWD"'
jtest '! ./jail --share-wd ro -- touch "$PWD"'
jtest './jail --share-wd rw -- ls "$PWD"'
jtest './jail --share-wd rw -- touch "$PWD"'
jtest '! ./jail --share-wd bad -- true'

jdescribe 'environment'
jtest './jail -e "EXPECTED_HOME=/home/${USER:-user}" -- sh -c "test \"\$HOME\" = \"\$EXPECTED_HOME\" && test -d \"\$HOME\""'
jtest './jail -e FOO=bar -- sh -c "test \"\$FOO\" = bar"'
jtest './jail -E HOME -- sh -c "test \"\$HOME\" = \"$HOME\""'
jtest './jail -e "EXPECTED_UID=$(id -u)" -e "EXPECTED_GID=$(id -g)" -e "EXPECTED_HOME=/home/${USER:-user}" -- sh -c "IFS=: read -r _ _ uid gid _ home _ < /etc/passwd && test \"\$uid\" = \"\$EXPECTED_UID\" && test \"\$gid\" = \"\$EXPECTED_GID\" && test \"\$home\" = \"\$EXPECTED_HOME\" && IFS=: read -r _ _ group_gid _ < /etc/group && test \"\$group_gid\" = \"\$EXPECTED_GID\" && test -r /etc/nsswitch.conf"'
jtest '! ./jail -E JAIL_TEST_ENV_DOES_NOT_EXIST -- true'
jtest './jail -E! JAIL_TEST_ENV_DOES_NOT_EXIST -- true'
jtest '! ./jail -E 1BAD -- true'
jtest '! ./jail -E! 1BAD -- true'
jtest './jail --home /tmp -- sh -c "test \"\$HOME\" = /tmp"'
jtest './jail --home /tmp -- sh -c "test \"\$PWD\" = /tmp"'
jtest './jail --home /tmp --wd / -- sh -c "test \"\$PWD\" = /"'
jtest './jail --share-home ro -- sh -c "test \"\$HOME\" = \"$HOME\""'
jtest './jail --share-home ro -- sh -c "test \"\$PWD\" = \"$PWD\""'
jtest './jail --share-home ro --wd /tmp -- sh -c "test \"\$PWD\" = /tmp"'
jtest './jail --share-home ro -- ls "$HOME"'
jtest '! ./jail --share-home ro -- touch "$HOME/.jail-test-share-home"'
jtest './jail --share-home rw -- touch "$HOME/.jail-test-share-home"'
jtest '! ./jail --home /tmp --share-home ro -- true'
rm -f "$HOME/.jail-test-share-home"

jdescribe 'persistent profile home'
profile_name="jail-test-profile-$$"
profile_dir="$HOME/.local/share/jail.sh/profiles/$profile_name"
profile_home_dir="$profile_dir/home"
profile_jail_home="/home/${USER:-user}"
rm -rf "$profile_dir"
jtest 'output="$(./jail -P "$profile_name" -- true 2>&1)" && [[ "$output" == *"using new profile $profile_name ($profile_dir)"* ]]'
jtest 'output="$(./jail -P "$profile_name" -- true 2>&1)" && [[ "$output" == *"reusing existing profile $profile_name ($profile_dir)"* ]]'
jtest './jail -P "$profile_name" -- sh -c "test \"\$HOME\" = \"$profile_jail_home\" && test \"\$PWD\" = \"$profile_jail_home\" && : > \"\$HOME/file\""'
jtest 'test -e "$profile_home_dir/file"'
jtest './jail -P "$profile_name" -- sh -c "test -e \"\$HOME/file\""'
jtest './jail -P "$profile_name" -- sh -c "IFS=: read -r _ _ _ _ _ home _ < /etc/passwd && test \"\$home\" = \"$profile_jail_home\""'
jtest './jail --gui -P "$profile_name" -- sh -c "test \"\$HOME\" = \"$profile_jail_home\" && test \"\$XDG_CACHE_HOME\" = /tmp"'
jtest '! ./jail -P bad/name -- true'
jtest '! ./jail -P "$profile_name" --home /tmp -- true'
rm -rf "$profile_dir"

jdescribe 'custom binds'
rm -f .jail-test-touch
jtest './jail -b "$PWD:$PWD:ro" -- ls "$PWD"'
jtest './jail -b ".:.:ro" -- ls "$PWD"'
jtest '! ./jail -b "$PWD:$PWD:ro" -- touch "$PWD/.jail-test-touch"'
jtest './jail -b "$PWD:$PWD:rw" -- ls "$PWD"'
jtest './jail -b "$PWD:$PWD:rw" -- touch "$PWD/.jail-test-touch"'
jtest './jail -b! "/jail-test-does-not-exist:/jail-test-does-not-exist:ro" -- true'
jtest '! ./jail -b "$PWD:$PWD" -- true'
jtest '! ./jail -b! "$PWD:$PWD" -- true'
jtest './jail -B "$PWD:ro" -- ls "$PWD"'
jtest './jail -B ".:ro" -- ls "$PWD"'
jtest '! ./jail -B "$PWD:ro" -- touch "$PWD/.jail-test-touch"'
jtest './jail -B "$PWD:rw" -- touch "$PWD/.jail-test-touch"'
jtest './jail -B! "/jail-test-does-not-exist:ro" -- true'
jtest '! ./jail -B "$PWD" -- true'
jtest '! ./jail -B "$PWD:bad" -- true'
jtest '! ./jail -B! "$PWD:bad" -- true'
rm -rf .jail-test-link .jail-test-link-dir .jail-test-link-target
mkdir .jail-test-link-target .jail-test-link-dir
touch .jail-test-link-target/file
ln -s .jail-test-link-target .jail-test-link
ln -s "$PWD/.jail-test-link-target" .jail-test-link-dir/target
jtest './jail -B "$PWD/.jail-test-link:ro" -- sh -c "test -e \"$PWD/.jail-test-link/file\" && test -e \"$PWD/.jail-test-link-target/file\""'
jtest '! ./jail -B "$PWD/.jail-test-link-dir:ro" -- sh -c "test -e \"$PWD/.jail-test-link-dir/target/file\""'
jtest './jail -B+ "$PWD/.jail-test-link-dir:ro" -- sh -c "test -e \"$PWD/.jail-test-link-dir/target/file\" && test -e \"$PWD/.jail-test-link-target/file\""'
jtest './jail -B+ ".jail-test-link-dir:ro" -- sh -c "test -e \"$PWD/.jail-test-link-dir/target/file\" && test -e \"$PWD/.jail-test-link-target/file\""'
rm -rf .jail-test-link .jail-test-link-dir .jail-test-link-target
rm -f .jail-test-touch

exit $status
