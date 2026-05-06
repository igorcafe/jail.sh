#!/usr/bin/env bash

set -u

green=$'\033[1;32m'
yellow=$'\033[1;33m'
red=$'\033[1;31m'
bold=$'\033[1m'
white=$'\033[1;37m'
reset=$'\033[0m'
status=0
add_home=""

cleanup () {
    if [[ "$add_home" != "" ]]
    then
        rm -rf "$add_home"
    fi
}

trap cleanup EXIT

jdescribe () {
    printf '\n%s%s%s\n' "$white" "$1" "$reset" >&2
}

jtest () {
    command="$1"
    description="${2:-}"
    display_command="$command"

    if [[ "$command" == '! '* ]]
    then
        display_command="${red}!${reset} ${command#! }"
    fi

    if output="$(eval "$command" 2>&1)"
    then
        if [[ "$description" != "" ]]
        then
            printf '%sPASS%s: %s\n$ %b\n' "$green" "$reset" "$description" "$display_command" >&2
        else
            printf '%sPASS%s: %b\n' "$green" "$reset" "$display_command" >&2
        fi
    else
        if [[ "$description" != "" ]]
        then
            printf '%sFAIL%s: %s\n$ %b\n' "$red" "$reset" "$description" "$display_command" >&2
        else
            printf '%sFAIL%s: %b\n' "$red" "$reset" "$display_command" >&2
        fi
        echo "$output" >&2
	      status=1
        return 1
    fi
}

jskip () {
    if [[ "$#" -lt 3 ]]
    then
        printf '%sFAIL%s: jskip requires: jskip "condition" jtest "command" ["description"] [...]\n' "$red" "$reset" >&2
        exit 1
    fi

    condition="$1"
    shift

    commands=()
    descriptions=()
    while [[ "$#" -gt 0 ]]
    do
        if [[ "$#" -lt 2 || "$1" != jtest ]]
        then
            printf '%sFAIL%s: jskip requires jtest "command" ["description"] pairs\n' "$red" "$reset" >&2
            exit 1
        fi

        commands+=("$2")
        shift 2

        if [[ "$#" -gt 0 && "$1" != jtest ]]
        then
            descriptions+=("$1")
            shift
        else
            descriptions+=("")
        fi
    done

    if output="$(eval "$condition" 2>&1)"
    then
        for i in "${!commands[@]}"
        do
            command="${commands[$i]}"
            description="${descriptions[$i]}"

            if [[ "$description" != "" ]]
            then
                printf '%sSKIP%s: %s\n$ %s\n' "$yellow" "$reset" "$description" "$command" >&2
            else
                printf '%sSKIP%s: %s\n' "$yellow" "$reset" "$command" >&2
            fi
            printf 'Reason: %s\n' "$condition" >&2
            if [[ "$output" != "" ]]
            then
                echo "$output" >&2
            fi
        done
        return 0
    fi

    for i in "${!commands[@]}"
    do
        jtest "${commands[$i]}" "${descriptions[$i]}"
    done
}

jdescribe 'command separator'
jtest './jail.sh -- pwd | grep -x "$HOME"' "PWD must equal HOME=$HOME"
jtest '! ./jail.sh -- ls | read -n1' "PWD must be empty if not binded"
jtest './jail.sh -- ls '$HOME'' "home must exist"
jtest './jail.sh -B "${PWD}:ro" -- pwd | grep -x $PWD' "if host PWD is mounted, sandbox PWD must be the same"
jtest '[[ "$(./jail.sh -- date +%z)" == "$(date +%z)" ]]' "timezone offset must match host"

jdescribe 'incorrect usage'
jtest '! ./jail'
jtest '! ./jail.sh ls'
jtest '! ./jail.sh --'

jdescribe 'add command'
add_home="$(mktemp -d)"
jtest 'mkdir -p "$add_home/.local/share/applications" && printf "[Desktop Entry]\nType=Application\nName=True\nExec=true %%F\n" > "$add_home/.local/share/applications/true.desktop"'
jtest 'add_output=$(printf "\n" | HOME="$add_home" XDG_DATA_HOME="$add_home/.local/share" EDITOR=true ./jail.sh add true 2>&1) && grep -F "Desktop true.desktop detected." <<< "$add_output" && grep -F "Create desktop entry \"True (sandboxed)\"? [Y/n]:" <<< "$add_output"'
jtest 'test -x "$add_home/.local/bin/true"'
jtest 'test -f "$add_home/.local/share/applications/true.jail.desktop"'
jtest 'grep -F "Name=True (sandboxed)" "$add_home/.local/share/applications/true.jail.desktop"'
jtest 'grep -F "Exec=$add_home/.local/bin/true %F" "$add_home/.local/share/applications/true.jail.desktop"'
jtest 'grep -F "X-Jail-Generated=true" "$add_home/.local/share/applications/true.jail.desktop"'
jtest 'grep -F "flags=(" "$add_home/.local/bin/true"'
jtest 'jail_path=$(type -P jail || printf "%s" "$PWD/./jail.sh"); grep -F "exec $jail_path \"\${flags[@]}\" -- $(realpath "$(type -P true)") \"\$@\"" "$add_home/.local/bin/true"'
jtest 'printf "[Desktop Entry]\nName=Manual\nExec=$add_home/.local/bin/true\n" > "$add_home/.local/share/applications/manual.jail.desktop"'
jtest 'HOME="$add_home" ./jail.sh rm true'
jtest '! test -e "$add_home/.local/bin/true"'
jtest '! test -e "$add_home/.local/share/applications/true.jail.desktop"'
jtest 'test -e "$add_home/.local/share/applications/manual.jail.desktop"'
jtest '! HOME="$add_home" ./jail.sh rm true'
jtest 'HOME="$add_home" EDITOR=true ./jail.sh add true'
jtest 'HOME="$add_home" ./jail.sh rm true'
jtest '! HOME="$add_home" EDITOR=true ./jail.sh add bad/name'

jdescribe 'builtin sh'
jtest './jail.sh -- bash -c "echo exit | sh"' "sh must be builtin"

jdescribe 'extra programs'
jtest './jail.sh -p printf -p cat -- sh -c "printf ok && cat /dev/null"'

jdescribe 'coreutils'
jtest './jail.sh --core -- sh -c "test \$(printf ok | wc -c) -eq 2"'
jtest './jail.sh --core -- sh -c "command -v ls && command -v cp && command -v sort"'

jdescribe 'symlinks'
jtest './jail.sh -p readlink --symlink /bin/sh /tmp/sh-link -- sh -c "test \"\$(readlink /tmp/sh-link)\" = /bin/sh"'
jtest '! ./jail.sh --symlink /bin/sh tmp/sh-link -- true'

jdescribe 'devices'
jtest './jail.sh -- ls /dev/null /dev/zero /dev/random /dev/urandom /dev/tty /dev/shm /dev/stdin /dev/stdout /dev/stderr' 'should have standard devices'
#jtest './jail.sh -d null -d null -- sh -c "test -e /dev/null"'
jtest "script -qefc './jail.sh -- sh -c \"test -t 0 && : < /dev/tty\"' /dev/null"
jtest "script -qefc 'before=\$(stty -g); ./jail.sh -- stty raw -echo; test \"\$(stty -g)\" = \"\$before\"' /dev/null"
#jtest '! ./jail.sh -d /dev/null -- true'
#jtest '! ./jail.sh -d ../null -- true'
jtest '! ./jail.sh -d jail-does-not-exist -- true'
#jtest './jail.sh -d! jail-does-not-exist -- true'


test_persistence () {
    jdescribe 'persistent profile: home'
    
    profile_name="jail-test-profile-$RANDOM"
    profile_dir="$HOME/.local/share/jail.sh/profiles/$profile_name"
    profile_home_dir="$profile_dir/home"
    profile_jail_home="/home/$USER"
    rm -rf "$profile_dir"
    
    jtest 'output="$(./jail.sh -P "$profile_name" -- true 2>&1)" && \
    	[[ "$output" == *"using new profile $profile_name ($profile_dir)"* ]]'
    jtest 'output="$(./jail.sh -P "$profile_name" -- true 2>&1)" && \
    	[[ "$output" == *"reusing existing profile $profile_name ($profile_dir)"* ]]'
    jtest './jail.sh -P "$profile_name" -- sh -c ": > \"\$HOME/file\""'
    jtest 'test -e "$profile_home_dir/file"'
    jtest './jail.sh -P "$profile_name" -- sh -c "test -e \"\$HOME/file\""'
    jtest './jail.sh -P "$profile_name" -- grep "$USER:x:$(id -u):$(id -g):$USER:$HOME:/bin/sh" /etc/passwd'
    jtest './jail.sh --gui -P "$profile_name" -- test "$HOME" = "$profile_jail_home"'
    jtest '! ./jail.sh -P bad/name -- true'
    
    rm -rf "$profile_dir"
}

test_persistence

jdescribe 'network'
host_net_ns="$(readlink /proc/self/ns/net)"
jtest '! ./jail.sh -- readlink /proc/self/ns/net | grep -F "'$host_net_ns'"' \
	    "must not have the same net ns if --net is not passed"

jtest './jail.sh --net -- readlink /proc/self/ns/net| grep -F "'$host_net_ns'"' \
	    "must have the same net ns if --net is passed"

jtest '! ./jail.sh -- curl http://google.com' 'cant cURL without --net'
jtest './jail.sh --net -- curl http://google.com' 'cURL a page'
jtest './jail.sh --net -- curl https://google.com' 'cURL with TLS'

jdescribe 'flag --gui: fonts'
jskip '[ ! -e /etc/fonts ]' \
      jtest './jail.sh --gui -- test -e /etc/fonts'
jskip '[ ! -L /etc/fonts/fonts.conf ]' \
      jtest 'font_bind=$(mktemp -d) && ./jail.sh --gui -B "${font_bind}:rw" -- sh -c "test -e /etc/fonts/fonts.conf"'
jtest 'font_home=$(mktemp -d) && mkdir -p "$font_home/fonts" && XDG_DATA_HOME="$font_home" ./jail.sh --gui -- test -e "$font_home/fonts"'

jdescribe 'flag --gui: audio'
jskip '[ ! -e /dev/snd ]' \
      jtest './jail.sh --gui -B "$PWD/testdata/short.wav:ro" -- ffplay -hide_banner -autoexit -i "$PWD/testdata/short.wav"' 'plays audio'

jdescribe 'flag --gui: video'
jskip '[ ! -e /dev/dri ]' \
      jtest './jail.sh --gui -B "$PWD/testdata/video.mp4:ro" -- ffplay -hide_banner -autoexit -i "$PWD/testdata/video.mp4"' 'plays video'

jdescribe 'flag --gui: input'
jskip '[ ! -e /sys/class/input -o ! -e /run/udev ]' \
      jtest './jail.sh --gui -- sh -c "test -e /sys/class/input && test -e /run/udev"'
jskip '[ ! -e /dev/input ]' \
      jtest './jail.sh --gui -- sh -c "test -e /dev/input"'

jdescribe 'environment'
jtest './jail.sh -e "EXPECTED_HOME=/home/${USER:-user}" -- sh -c "test \"\$HOME\" = \"\$EXPECTED_HOME\" && test -d \"\$HOME\""'
jtest './jail.sh -e FOO=bar -- sh -c "test \"\$FOO\" = bar"'
jtest './jail.sh -E HOME -- sh -c "test \"\$HOME\" = \"$HOME\""'
jtest './jail.sh -e "EXPECTED_UID=$(id -u)" -e "EXPECTED_GID=$(id -g)" -e "EXPECTED_HOME=/home/${USER:-user}" -- sh -c "IFS=: read -r _ _ uid gid _ home _ < /etc/passwd && test \"\$uid\" = \"\$EXPECTED_UID\" && test \"\$gid\" = \"\$EXPECTED_GID\" && test \"\$home\" = \"\$EXPECTED_HOME\" && IFS=: read -r _ _ group_gid _ < /etc/group && test \"\$group_gid\" = \"\$EXPECTED_GID\" && test -r /etc/nsswitch.conf"'
jtest '! ./jail.sh -E JAIL_TEST_ENV_DOES_NOT_EXIST -- true'
jtest './jail.sh -E! JAIL_TEST_ENV_DOES_NOT_EXIST -- true'
jtest '! ./jail.sh -E 1BAD -- true'
jtest '! ./jail.sh -E! 1BAD -- true'

jdescribe 'custom binds'
rm -f .jail-test-touch
jtest './jail.sh -b "$PWD:$PWD:ro" -- ls "$PWD"'
jtest './jail.sh -b ".:.:ro" -- ls "$PWD"'
jtest '! ./jail.sh -b "$PWD:$PWD:ro" -- touch "$PWD/.jail-test-touch"'
jtest './jail.sh -b "$PWD:$PWD:rw" -- ls "$PWD"'
jtest './jail.sh -b "$PWD:$PWD:rw" -- touch "$PWD/.jail-test-touch"'
jtest './jail.sh -b! "/jail-test-does-not-exist:/jail-test-does-not-exist:ro" -- true'
jtest '! ./jail.sh -b "$PWD:$PWD" -- true'
jtest '! ./jail.sh -b! "$PWD:$PWD" -- true'
jtest './jail.sh -B "$PWD:ro" -- ls "$PWD"'
jtest './jail.sh -B ".:ro" -- ls "$PWD"'
jtest '! ./jail.sh -B "$PWD:ro" -- touch "$PWD/.jail-test-touch"'
jtest './jail.sh -B "$PWD:rw" -- touch "$PWD/.jail-test-touch"'
jtest './jail.sh -B! "/jail-test-does-not-exist:ro" -- true'
jtest './jail.sh -B+! "/jail-test-does-not-exist:ro" -- true'
jtest '! ./jail.sh -B "$PWD" -- true'
jtest '! ./jail.sh -B "$PWD:bad" -- true'
jtest '! ./jail.sh -B! "$PWD:bad" -- true'
rm -rf .jail-test-link .jail-test-link-dir .jail-test-link-target
mkdir .jail-test-link-target .jail-test-link-dir
touch .jail-test-link-target/file
ln -s .jail-test-link-target .jail-test-link
ln -s "$PWD/.jail-test-link-target" .jail-test-link-dir/target
jtest './jail.sh -B "$PWD/.jail-test-link:ro" -- sh -c "test -e \"$PWD/.jail-test-link/file\" && test -e \"$PWD/.jail-test-link-target/file\""'
jtest '! ./jail.sh -B "$PWD/.jail-test-link-dir:ro" -- sh -c "test -e \"$PWD/.jail-test-link-dir/target/file\""'
jtest './jail.sh -B+ "$PWD/.jail-test-link-dir:ro" -- sh -c "test -e \"$PWD/.jail-test-link-dir/target/file\" && test -e \"$PWD/.jail-test-link-target/file\""'
jtest './jail.sh -B+ ".jail-test-link-dir:ro" -- sh -c "test -e \"$PWD/.jail-test-link-dir/target/file\" && test -e \"$PWD/.jail-test-link-target/file\""'
rm -rf .jail-test-link .jail-test-link-dir .jail-test-link-target
rm -f .jail-test-touch

exit $status
