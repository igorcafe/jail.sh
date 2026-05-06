# jail.sh

`jail.sh` is a small Bash sandbox tool based on Bubblewrap (`bwrap`) for running a command in a minimal, isolated filesystem and environment.

## Security Notice

This project is experimental. I am not an infosec professional, and this tool may contain security vulnerabilities. Do not rely on it as a hardened sandbox for untrusted code without reviewing and testing it for your threat model.

## Default Behavior

By default it only exposes:

- `/bin/sh`
- the requested executable and its dependencies
- essential devices such as `/dev/null`, `/dev/zero`, `/dev/random`, `/dev/urandom`, `/dev/tty`, and `/dev/shm`
- a minimal `/etc/passwd`, `/etc/group`, and `/etc/nsswitch.conf`
- `/proc` for the jailed process namespace
- default directories: `/tmp` and an empty home directory
- environment variables: `TERM`, a minimal `PATH`, a default `HOME`, and locale-related variables from the host when set

## Requirements

- Bash
- Bubblewrap (`bwrap`)
- Standard Linux tools such as `ldd`, `realpath`, `id`, and `stty`
- Optional: `nix-store`, for better Nix store dependency binding

## Usage

```sh
../jail.sh [options] -- command [args...]
../jail.sh add command
../jail.sh rm command
```

Examples:

```sh
../jail.sh -- emacs
../jail.sh add emacs
../jail.sh rm emacs
../jail.sh -p printf -- sh -c 'printf ok'
../jail.sh -b /tmp:/host-tmp:rw -- sh
../jail.sh --net -- curl https://example.com
../jail.sh -P browser --gui -- firefox
```

Run `./jail.sh` with no arguments to print the full option list.

`../jail.sh add command` creates or edits `~/.local/bin/command` and opens it in your editor.

`../jail.sh rm command` removes the existing `~/.local/bin/command` wrapper.

## Debugging

Set `DEBUG` to print resolution details to stderr:

```sh
DEBUG=1 ../jail.sh -- sh
```

Debug logs include only the main executable and its Nix store or shared library dependencies.

## Options

- `-p PROGRAM`
  Expose an extra program inside `/bin`.

- `-b SRC:DEST:MODE`
  Bind mount `SRC` at `DEST`. Relative paths are resolved from the host working directory. `MODE` must be `ro` or `rw`.

- `-B PATH:MODE`
  Short for `-b PATH:PATH:MODE`. Relative paths are resolved from the host working directory.

- `-B+ PATH:MODE`
  Like `-B`, and recursively bind external symlink targets.

- `-d DEVICE`
  Expose `/dev/DEVICE` inside the jail.

- `-b!`, `-B!`, `-B+!`, `-d!`, `-E!`
  Optional variants that ignore missing host resources.

- `--core`
  Expose available coreutils programs.

- `--gui`
  Expose GUI, sound, DRI devices, and driver paths.

- `-e NAME=VALUE`
  Set an environment variable inside the jail.

- `-E NAME`
  Copy an environment variable from the host.

- `-P NAME`
  Persist `HOME` in `~/.local/share/jail.sh/profiles/NAME/home`, mounted inside the jail as `/home/$USER`. Prints whether it is using a new profile or reusing an existing one.

- `--symlink SRC DEST`
  Create symlink `DEST -> SRC` inside the jail. `DEST` must be absolute.

- `--net`
  Allow access to the host network namespace.

## Tests

```sh
./tests.sh
```
