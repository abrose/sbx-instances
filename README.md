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

Proved with sbx v0.53.0 in a named instance: the command in the sandbox gets `--app-name x` unchanged, as it gets
an empty argument, an argument with a space, and `*`. With no `--` before the command, the wrapper refuses.

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
in each line. A line that starts with `#` is a comment. The list file can be a link, for example into a dotfiles
repo: `remove` writes through the link.

Let the wizard add the names. Each sbx call with a name creates two small folders of that instance (about 52 KB),
also `sbx daemon status`. So a typing error in a list that you edit by hand creates an instance at the next check
or build. The check names the typing error in its `FAIL` line, and the build of sbx-stack-base loads no image into
an instance that is not signed in. `remove` never passes a name that is no instance name to sbx.

### The wizard

`sbx-instance add` asks four questions, shows one summary, and acts only after a yes. A no changes nothing and
exits with status 1. The wizard needs `jq`.

1. The name of the instance.
2. The network policy of a new instance: `deny-all` (the proposal), `balanced` or `allow-all`.
3. The instance to copy the changed sbx settings from, or `none`. A new instance has the defaults of sbx: it sends
   telemetry, and it allows a kit only from Docker Hub.
4. The folders that select the instance.

Then it does these steps. It leaves a step that is done already, so a second run repairs an instance. Only the
label is set again in each run: sbx updates it in place, so the result is the same.

1. It adds the name to the list.
2. It runs `sbx login` in the instance when the instance is not signed in to Docker. You sign in in the terminal.
   With no terminal, the wizard runs no sign-in: it stops and prints the command.
3. It sets the network policy when the instance has none.
4. It sets the label of the instance (see "The label of an instance").
5. It copies each setting that the source instance changed and that differs. When sbx asks for a restart of the
   daemon, the wizard restarts the daemon of a new instance. It does not restart the daemon of `default` or of
   an instance that was on the list before: such an instance can have sandboxes in use. It prints the command.
   When a later setting fails, the wizard stops and prints the restart command for the settings it set before.
6. It writes the marker files. It never changes a marker file that names another instance.
7. It prints the steps that are left for you: load your template, create a sandbox, and run `/login` in Claude in
   that sandbox. One Claude login holds for all sandboxes of the instance.

Each answer has an option, for a script:

```bash
sbx-instance add alpha --policy deny-all --settings-from default --folder ~/work/alpha --yes
```

With no terminal, each answer needs its option, and no `--folder` means no folder.

### The check

`sbx-instance check` prints one `PASS` or `FAIL` line for each test, and exits with status 1 after a `FAIL`:

- The wrapper is the first `sbx` in `PATH`.
- `jq` is in `PATH`. With no `jq`, the check skips the test of the label.
- A real `sbx` is in `PATH`.
- For each named instance on the list: the socket path of its daemon holds its name. This proves that
  `--app-name` still separates the instances. If this test fails, do not use the named instances with that sbx.
- Each instance on the list is signed in to Docker and has a network policy.
- Each instance on the list labels its sandboxes. For this test the check asks sbx for one row of the secret
  store, the row of the variable `SBX_INSTANCE`. It prints no row of the store. It prints only the placeholder of
  that row when the placeholder names another instance; the placeholder of the label is no secret.

The check changes nothing. A daemon that did not run before the check is stopped again, unless a sandbox runs in
it at the end of the check: then a `NOTE` line says that the daemon stays running.

Not proved: what `sbx policy ls` prints for an instance with no network policy. The test looks for a row that
starts with `default-`, which each instance with a policy has.

## The label of an instance

A sandbox does not know its instance: sbx gives the VM the name of the sandbox, and no trace of `--app-name`. So
each instance labels its own sandboxes. In a new sandbox of a labeled instance, the variable `SBX_INSTANCE` holds
the name of the instance. A status line or a shell prompt in the sandbox can show it.

The wizard stores the label with a feature of sbx that has another purpose, a custom secret:

```bash
sbx secret set-custom --host sbx-instance.invalid --env SBX_INSTANCE --placeholder <name> --value <name>
```

sbx sets the variable of a custom secret to its placeholder in each new sandbox, and here the placeholder is the
name of the instance. Nothing in it is a secret. The host does not exist (`.invalid` is a reserved name), so the
proxy of sbx never has a request to put the value into.

- **`sbx secret ls` shows one row for the label** in each instance, below "CUSTOM SECRETS".
- **A sandbox that exists has no label.** sbx sets the variable when it creates a sandbox, not at a later start
  (proved with sbx v0.53.0). The sandbox gets the label at its next create.
- **`sbx secret rm --all` removes the label.** `sbx-instance check` then fails for that instance and names the
  repair: `sbx-instance add <name>`. A second run of the wizard sets the label again and changes nothing else.
- **An `env` value of the same name in a project file** is not proved: do not set `SBX_INSTANCE` there.
- **`sbx secret set-custom` is experimental in sbx.** If Docker changes it, the label is gone and the check says
  so. The instances still work.

## Several projects in one sandbox

Project folders below one parent folder can share one sandbox. The sandbox mounts the parent folder, and each agent
session starts in a project folder. Several sessions can run at the same time.

1. Create the sandbox in the parent folder, one time:

   ```bash
   cd ~/work
   sbx run -d claude --name claude-work
   ```

2. In each terminal, start Claude in a project folder:

   ```bash
   cd ~/work/project-a
   sbx exec -it -w "$PWD" claude-work claude
   ```

sbx mounts the workspace at the same path as on the host, so `"$PWD"` is also the path in the sandbox. For one
session in the terminal of `sbx run`, the help of sbx gives `sbx run --name claude-work -w project-a`: there `-w` is
relative to the workspace and holds for that session only (not proved).

Proved with sbx v0.54.0 in a named instance:

- Two `claude -p` sessions ran at the same time in one sandbox. Each one answered with its own project folder.
- `sbx exec -it` gives the session a terminal (`/dev/pts/0`, `TERM=xterm-256color`).
- `claude` in `sbx exec` gets the setup of `sbx run`. The Claude kit puts the bypass mode, its hooks and its status
  line into `~/.claude/settings.json`, not into arguments.

Not proved: the full screen of Claude in `sbx exec -it`, and the sbx status of a sandbox with two sessions.

- **The Claude login comes from the instance.** In an instance with no Claude login, `claude` in the sandbox prints
  `Not logged in · Please run /login`, and the variable `SBX_CRED_ANTHROPIC_MODE` in the sandbox is `none`. In an
  instance with a login, `sbx secret ls` shows the row `anthropic` with `(oauth configured)`.
- **The wrapper selects the instance from the project folder,** not from the parent folder. Keep all project folders
  below the marker file of the instance of the sandbox. A project folder with a marker file for another instance
  sends `sbx exec` to that instance, where the sandbox does not exist: sbx exits with status 125.
- **A session of `sbx exec` cannot detach.** When its terminal closes, the session ends. The sandbox and the other
  sessions keep running. `sbx exec` starts a stopped sandbox first.
- **Each session can write into all project folders,** because the workspace is the parent folder. For a project
  that the other sessions must not change, use a sandbox of its own. Mount other folders read-only there:
  `sbx run claude ./project-a ./project-b:ro`.

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
- **A host command of a project file selects its own instance.** sbx runs a `lifecycle` host command in the folder
  of the project file, with a `PATH` in which the wrapper is found (proved with sbx v0.53.0). So an `sbx` call in
  a host command uses the instance of the folder of the project file. The sandbox itself is in the instance of
  the folder where you ran `sbx env create`. Run `sbx env create` in the folder of the project file, or keep both
  folders below one marker file. Else the host command talks to another instance than the one with the sandbox.
- **A shell that was open at the install** can call the real `sbx` until `rehash` (zsh) or `hash -r` (bash). Such
  a call runs in the instance of sbx itself, with no message, also in a folder with a marker file. `type sbx`
  shows which one a shell calls: it must print the link of the wrapper.

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
