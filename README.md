# sbx-instances

One sbx instance for each Claude account. A wrapper `sbx` selects the instance from the folder that you work in.

Docker Sandboxes (`sbx`) has a hidden argument, `--app-name <name>`. It gives a fully separate instance: its own
daemon, sandboxes, secrets, Docker sign-in, network policy, templates, settings and Claude login. This repo makes
the argument safe to use each day:

- A marker file `.sbx-instance` in a folder names the instance for that folder and all folders below it.
- The wrapper `sbx` reads the nearest marker file and runs the real `sbx` in that instance.
- With no marker file, the wrapper refuses. So no command goes to a wrong instance without a word.

Tested with sbx v0.53.0, with bash 3.2 and bash 5, on macOS.

## Install

> **From the install on, a plain `sbx` in a folder with no marker file refuses.**
> If you have sandboxes in the instance of sbx itself (no `--app-name`), set that instance up first. The steps
> below do that.

1. Run the wizard for the instance of sbx itself, and name each project folder that has sandboxes there. Before
   the install, call the tool by its path:

   ```bash
   bin/sbx-instance add default
   ```

2. Link the wrapper and the tool into `~/.local/bin` (or into the folder in `SBX_INSTANCES_BIN`). That folder must
   be before the folder of the real `sbx` in `PATH`.

   ```bash
   ./install.sh
   ```

   `install.sh` does not replace a file that is not its own link. At its end it runs `sbx-instance check`.

   A shell that is open at the install can still call the real `sbx`, with no instance and no message: a shell
   remembers the path of a command. Open a new terminal, or run `rehash` (zsh) or `hash -r` (bash) in each open
   shell.

3. Add an instance for each account:

   ```bash
   sbx-instance add
   ```

To remove the tool, delete the two links `sbx` and `sbx-instance`.

## The marker file

A marker file is a file with the name `.sbx-instance`. It holds one line: the name of an instance.

```text
alpha
```

- The wrapper takes the nearest marker file: the first one from the working folder upward, up to and with the
  home folder. A marker file further up does not count then. So a marker file in a folder overrides one above it.
- The wrapper uses the physical path of the working folder. A link to a folder gets the instance of the folder.
- A working folder outside the home folder has no marker file.
- The name must be on the list (see `sbx-instance list`). If the name is not on the list, the wrapper refuses. It
  does not go on to a marker file further up.
- The name `default` means the instance of sbx itself: the wrapper adds no `--app-name`.

An instance name has small letters, digits and dashes, starts with a letter or a digit, and has at most 31
characters.

## What the wrapper does

The first rule that fits decides.

| # | The call | What the wrapper does |
|---|---|---|
| 1 | An argument before the first `--` is `--app-name` or `--app-name=...` | Refuses |
| 2 | The first argument is `version`, `help`, `--help`, `-h`, `completion`, or starts with `__complete` | Runs the real `sbx` unchanged |
| 3 | No marker file | Refuses |
| 4 | The marker file names no valid name, or a name that is not on the list | Refuses |
| 5 | The marker file names `default` | Runs the real `sbx` unchanged |
| 6 | The marker file names another instance | Runs the real `sbx --app-name <name>` with the arguments |

A refusal prints one message to stderr, runs nothing, and exits with status 64. With no real `sbx` in `PATH`, the
exit status is 127. The wrapper has no variable for the selection: the working folder is its only input.

For a command in a sandbox that has an argument with the name `--app-name`, put `--` before the command:

```bash
sbx exec <sandbox> -- <command> --app-name x
```

## The tool `sbx-instance`

| Command | What it does |
|---|---|
| `sbx-instance add [<name>]` | The wizard: sets up an instance and its folders |
| `sbx-instance list` | Prints the names on the list, one in each line |
| `sbx-instance which` | Prints the instance that a plain `sbx` uses in the working folder (the name on stdout, the marker file on stderr). It refuses with status 64 when the wrapper is not the first `sbx` in `PATH` |
| `sbx-instance run <name> -- <sbx arguments>` | Runs `sbx` in a named instance, from any folder. The marker files do not count |
| `sbx-instance check` | Tests the setup. Run it after each update of sbx |
| `sbx-instance remove <name>` | Takes a name off the list. It deletes nothing else |

The list is the file `sbx-instances/instances` below `~/.config` (or below `XDG_CONFIG_HOME`). It holds one name
in each line. A line that starts with `#` is a comment.

### The wizard

`sbx-instance add` asks four questions, shows one summary, and acts only after a yes. A no changes nothing and
exits with status 1. The wizard needs `jq`.

1. The name of the instance.
2. The network policy of a new instance: `deny-all` (the proposal), `balanced` or `allow-all`.
3. The instance to copy the changed sbx settings from, or `none`. A new instance has the defaults of sbx: it sends
   telemetry, and it allows a kit only from Docker Hub.
4. The folders that select the instance.

Then it does these steps. It leaves a step that is done already, so a second run repairs an instance:

1. It adds the name to the list.
2. It runs `sbx login` in the instance when the instance is not signed in to Docker. You sign in in the terminal.
   With no terminal, the wizard runs no sign-in: it stops and prints the command.
3. It sets the network policy when the instance has none.
4. It copies each setting that the source instance changed and that differs. When sbx asks for a restart of the
   daemon, the wizard restarts the daemon of a new instance. It does not restart the daemon of `default` or of
   an instance that was on the list before: such an instance can have sandboxes in use. It prints the command.
5. It writes the marker files. It never changes a marker file that names another instance.
6. It prints the steps that are left for you: load your template, create a sandbox, and run `/login` in Claude in
   that sandbox. One Claude login holds for all sandboxes of the instance.

Each answer has an option, for a script:

```bash
sbx-instance add alpha --policy deny-all --settings-from default --folder ~/work/alpha --yes
```

With no terminal, each answer needs its option, and no `--folder` means no folder.

### The check

`sbx-instance check` prints one `PASS` or `FAIL` line for each test, and exits with status 1 after a `FAIL`:

- The wrapper is the first `sbx` in `PATH`.
- A real `sbx` is in `PATH`.
- For each named instance on the list: the socket path of its daemon holds its name. This proves that
  `--app-name` still separates the instances. If this test fails, do not use the named instances with that sbx.
- Each instance on the list is signed in to Docker and has a network policy.

The check changes nothing. A daemon that did not run before the check is stopped again.

Not proved: what `sbx policy ls` prints for an instance with no network policy. The test looks for a row that
starts with `default-`, which each instance with a policy has.

## Limits

- **`--app-name` is a hidden argument of sbx.** Docker can remove it. Then the real `sbx` fails with an unknown
  argument, and `sbx-instance check` fails.
- **A call of the real `sbx` by its full path skips the wrapper.** It runs in the instance of sbx itself. An empty
  instance there, with no sign-in, makes such a call fail.
- **The kit approvals are one file for all instances.** An approval in one instance holds in all.
- **A daemon that is not the first one has no kit registry facade,** and its `llmman` stands by. Kits from a local
  folder, from Docker Hub and from a `git+https` source work there.
- **The settings of sbx are separate for each instance.** A setting that you change later holds for one instance.
- **Each instance holds its own copy of a template.**
- **A marker file from a sandbox.** A sandbox can write into its workspace, so an agent can put a `.sbx-instance`
  file there. It is then the nearest marker file for a plain `sbx` in that folder, and it wins when its name is on
  the list. Keep your marker files above the workspaces, and look at `sbx-instance which` when in doubt.
- **Shell completion** asks the real `sbx` with no instance. It completes the sandbox names of the instance of sbx
  itself.

## Tests

The unit tests run with a stub in the place of the real `sbx`, and with a home folder below a temporary folder.
They do not touch your instances.

```bash
for name in lib sbx sbx-instance add check install; do bash "tests/$name.sh" || break; done
```

Each test runs the scripts with the bash that runs the test. Run them with bash 5 and with the bash of macOS
(3.2). A plain `bash` can be either one: `bash --version` shows it.

```bash
for name in lib sbx sbx-instance add check install; do /opt/homebrew/bin/bash "tests/$name.sh" || break; done
```

```bash
for name in lib sbx sbx-instance add check install; do /bin/bash "tests/$name.sh" || break; done
```
