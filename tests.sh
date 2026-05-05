#!/usr/bin/env bash

set -u

green=$'\033[1;32m'
yellow=$'\033[1;33m'
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
jtest './jail -- pwd | grep -x "$HOME"' "PWD must equal HOME=$HOME"
jtest '! ./jail -- ls | read -n1' "PWD must be empty if not binded"
jtest './jail -- ls '$HOME'' "home must exist"
jtest './jail -B "${PWD}:ro" -- pwd | grep -x $PWD' "if host PWD is mounted, sandbox PWD must be the same"

jdescribe 'incorrect usage'
jtest '! ./jail'
jtest '! ./jail ls'
jtest '! ./jail --'

jdescribe 'builtin sh'
jtest './jail -- bash -c "echo exit | sh"' "sh must be builtin"

jdescribe 'extra programs'
jtest './jail -p printf -p cat -- sh -c "printf ok && cat /dev/null"'

jdescribe 'coreutils'
jtest './jail --core -- sh -c "test \$(printf ok | wc -c) -eq 2"'
jtest './jail --core -- sh -c "command -v ls && command -v cp && command -v sort"'

jdescribe 'symlinks'
jtest './jail -p readlink --symlink /bin/sh /tmp/sh-link -- sh -c "test \"\$(readlink /tmp/sh-link)\" = /bin/sh"'
jtest '! ./jail --symlink /bin/sh tmp/sh-link -- true'

jdescribe 'devices'
jtest './jail -- ls /dev/null /dev/zero /dev/random /dev/urandom /dev/tty /dev/shm /dev/stdin /dev/stdout /dev/stderr' 'should have standard devices'
#jtest './jail -d null -d null -- sh -c "test -e /dev/null"'
jtest "script -qefc './jail -- sh -c \"test -t 0 && : < /dev/tty\"' /dev/null"
jtest "script -qefc 'before=\$(stty -g); ./jail -- stty raw -echo; test \"\$(stty -g)\" = \"\$before\"' /dev/null"
#jtest '! ./jail -d /dev/null -- true'
#jtest '! ./jail -d ../null -- true'
jtest '! ./jail -d jail-does-not-exist -- true'
#jtest './jail -d! jail-does-not-exist -- true'


test_persistence () {
    jdescribe 'persistent profile: home'
    
    profile_name="jail-test-profile-$RANDOM"
    profile_dir="$HOME/.local/share/jail.sh/profiles/$profile_name"
    profile_home_dir="$profile_dir/home"
    profile_flags="$profile_dir/flags"
    profile_jail_home="/home/$USER"
    rm -rf "$profile_dir"
    
    jtest 'output="$(./jail -P "$profile_name" -- true 2>&1)" && \
    	[[ "$output" == *"using new profile $profile_name ($profile_dir)"* ]]'
    jtest 'output="$(./jail -P "$profile_name" -- true 2>&1)" && \
    	[[ "$output" == *"reusing existing profile $profile_name ($profile_dir)"* ]]'
    jtest './jail -P "$profile_name" -- sh -c ": > \"\$HOME/file\""'
    jtest 'test -e "$profile_home_dir/file"'
    jtest './jail -P "$profile_name" -- sh -c "test -e \"\$HOME/file\""'
    jtest './jail -P "$profile_name" -- grep "$USER:x:$(id -u):$(id -g):$USER:$HOME:/bin/sh" /etc/passwd'
    jtest './jail --gui -P "$profile_name" -- test "$HOME" = "$profile_jail_home"'
    jtest '! ./jail -P bad/name -- true'
    
    
    jdescribe 'persistent profile: flags'
    echo "
    --net
    -B $PWD/testdata/short.wav:ro
    -B $PWD/testdata/video.mp4:ro
    " >> "$profile_flags"
    jtest './jail -P "$profile_name" -- test -e /etc/hosts'
    jtest './jail -P "$profile_name" -- ls "$PWD/testdata/short.wav" "$PWD/testdata/video.mp4"' \
    	    "should use bindings from flags file"
    
    rm -rf "$profile_dir"
}

test_persistence

jdescribe 'network'
host_net_ns="$(readlink /proc/self/ns/net)"
jtest '! ./jail -- readlink /proc/self/ns/net | grep -F "'$host_net_ns'"' \
	    "must not have the same net ns if --net is not passed"

jtest './jail --net -- readlink /proc/self/ns/net| grep -F "'$host_net_ns'"' \
	    "must have the same net ns if --net is passed"

jtest '! ./jail -- curl http://google.com' 'cant cURL without --net'
jtest './jail --net -- curl http://google.com' 'cURL a page'
jtest './jail --net -- curl https://google.com' 'cURL with TLS'

jdescribe 'flag --gui: fonts'
jskip '[ ! -e /etc/fonts ]' \
      jtest './jail --gui -- test -e /etc/fonts'

jdescribe 'flag --gui: audio'
jskip '[ ! -e /dev/snd ]' \
      jtest './jail --gui -B "$PWD/testdata/short.wav:ro" -- ffplay -hide_banner -autoexit -i "$PWD/testdata/short.wav"' 'plays audio'

jdescribe 'flag --gui: video'
jskip '[ ! -e /dev/dri ]' \
      jtest './jail --gui -B "$PWD/testdata/video.mp4:ro" -- ffplay -hide_banner -autoexit -i "$PWD/testdata/video.mp4"' 'plays video'

jdescribe 'flag --gui: input'
jskip '[ ! -e /sys/class/input -o ! -e /run/udev ]' \
      jtest './jail --gui -- sh -c "test -e /sys/class/input && test -e /run/udev"'
jskip '[ ! -e /dev/input ]' \
      jtest './jail --gui -- sh -c "test -e /dev/input"'

jdescribe 'environment'
jtest './jail -e "EXPECTED_HOME=/home/${USER:-user}" -- sh -c "test \"\$HOME\" = \"\$EXPECTED_HOME\" && test -d \"\$HOME\""'
jtest './jail -e FOO=bar -- sh -c "test \"\$FOO\" = bar"'
jtest './jail -E HOME -- sh -c "test \"\$HOME\" = \"$HOME\""'
jtest './jail -e "EXPECTED_UID=$(id -u)" -e "EXPECTED_GID=$(id -g)" -e "EXPECTED_HOME=/home/${USER:-user}" -- sh -c "IFS=: read -r _ _ uid gid _ home _ < /etc/passwd && test \"\$uid\" = \"\$EXPECTED_UID\" && test \"\$gid\" = \"\$EXPECTED_GID\" && test \"\$home\" = \"\$EXPECTED_HOME\" && IFS=: read -r _ _ group_gid _ < /etc/group && test \"\$group_gid\" = \"\$EXPECTED_GID\" && test -r /etc/nsswitch.conf"'
jtest '! ./jail -E JAIL_TEST_ENV_DOES_NOT_EXIST -- true'
jtest './jail -E! JAIL_TEST_ENV_DOES_NOT_EXIST -- true'
jtest '! ./jail -E 1BAD -- true'
jtest '! ./jail -E! 1BAD -- true'

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
jtest './jail -B+! "/jail-test-does-not-exist:ro" -- true'
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
