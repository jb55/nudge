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
    [--action ID=LABEL]... [--env KEY=VALUE]... [--avatar PNG [--sender NAME]]
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

## Avatars

`--avatar PNG` (with `--sender NAME`, default the title) posts the
notification as an incoming message from that person: macOS draws the
avatar as the main icon, with Nudge's bell as a small badge. Any image
works, so it can be a person's picture or a per-source icon. macOS shows
only the sender's name and the body of such a notification, so nudge moves
the title and subtitle to the body's first line (the title only when it
isn't the sender's name). `--image` still sets the thumbnail.

This needs Apple's Communication Notifications entitlement, which a
provisioning profile has to grant:

1. In the developer portal, create the App ID `com.jb55.nudge` with the
   Communication Notifications capability, register your Mac (Devices, +,
   Platform: **macOS**; an Apple silicon Mac's Provisioning UDID from
   `system_profiler SPHardwareDataType` registered under iOS shows up as
   an "iPod" and can't be used), and make a macOS App Development profile
   for that App ID, your certificate and the Mac.
2. Save it as `~/.config/nudge/nudge.provisionprofile` (or point
   `NUDGE_PROFILE` at it) and run `./build.sh`, which embeds it and signs
   with the entitlement. It says `embedding …` when it does.

Without a profile, or if anything about the message fails, `--avatar` falls
back to a plain notification. Checked on macOS 26.6 with an app posting its
own notifications, no notification service extension. Message
notifications can be allowed through a Focus, which plain ones aren't by
default.

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
