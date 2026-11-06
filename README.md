# nudge

Post macOS notifications from the command line, from an app of your own:
its own icon on the left, an image thumbnail on the right, in-place
replacement, click-to-open, and buttons that run commands you configure.

terminal-notifier always shows its own Terminal icon on the left (`-appIcon`
has no effect on macOS 26), and osascript shows Script Editor's, takes no
image and no click URL. nudge is a small signed app bundle that posts
through `UNUserNotificationCenter`, so the notifications are its own.

## Build and install

```
./build.sh
```

compiles `main.swift` with the Command Line Tools' `swiftc` (no Xcode
project), assembles `~/Applications/Nudge.app` (`$NUDGE_INSTALL_DIR`
overrides the folder), makes its `.icns` from `icon.png` with `sips` and
`iconutil`, signs it, registers it with LaunchServices, and launches it once
with `--authorize`.

- `CODESIGN_IDENTITY` picks the signing identity (default: the author's
  Apple Development certificate; `security find-identity -v -p codesigning`
  lists yours, `-` signs ad hoc).
- `SWIFT_DEVELOPER_DIR` picks the toolchain (default
  `/Library/Developer/CommandLineTools`). It's not `DEVELOPER_DIR`, which a
  nix shell points at an SDK with no `swiftc`.
- `make-icon.py` draws `icon.png` (stdlib only); rerun it after changing
  the bell.

The first build asks for notification permission. If no prompt appears and
posts exit 2, turn Nudge on in System Settings > Notifications.

## Posting

```
~/Applications/Nudge.app/Contents/MacOS/Nudge --title T --message M \
    [--subtitle S] [--url U] [--image PNG] [--group G] [--thread T] \
    [--action ID=LABEL]... [--env KEY=VALUE]...
```

- `--group`: the request identifier. A later post with the same group
  replaces the earlier one in place, with a fresh banner.
- `--thread` (default: the group): posts with the same thread stack
  together in Notification Center.
- `--image`: shown as the thumbnail. nudge attaches a temp copy, since
  attaching moves the file.
- `--url`: opened when the notification is clicked. macOS relaunches the
  app for the click, so this works after the posting process has exited.

Exit status: 0 posted, 2 notifications not allowed, 3 failed, 64 usage.
`Nudge --authorize` asks for permission without posting.

## Buttons

Each `--action ID=LABEL` adds a button. Clicking it runs the command
configured for that id in `$XDG_CONFIG_HOME/nudge/actions.json` (default
`~/.config/nudge/actions.json`):

```json
{
  "handle-review": {
    "label": "Handle Review",
    "command": ["/Users/you/bin/handle-review"]
  }
}
```

- `command` is an argv list whose first element is an absolute path. It
  runs detached, from your home directory, with stdin closed and output
  appended to `~/Library/Logs/nudge-actions.log`.
- Its environment is nudge's (launchd's minimal one: use absolute paths, or
  `["/bin/bash", "-lc", "..."]`), plus each `--env KEY=VALUE` from the post
  and `NUDGE_ACTION=<id>`.
- The command is read from the file when the button is clicked, never from
  the notification, and the poster's values reach it only as environment
  variables, never spliced into a shell string.
- nudge reads only `command`. Other keys are left for callers that decide
  which buttons to offer (`label` above; gitlab-notify adds `kinds`).
- With the default Banners style, buttons show on hover or under
  "Options"; the Alerts style keeps them on screen.
- A failure to run the command goes to the unified log:
  `log show --last 10m --predicate 'process == "Nudge"'`.

## History

nudge began as `contrib/gitlab-notify/macos` in
[hookstr](https://github.com/jb55/hookstr) (GitLabNotify.app, bundle id
`com.jb55.hookstr.gitlab-notify`) and was split out with its history.
gitlab-notify still uses it as its preferred notifier on macOS.
