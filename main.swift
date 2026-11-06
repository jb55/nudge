// nudge: post a macOS notification from the command line. Posting through
// UNUserNotificationCenter from a bundle of our own is what gets our own
// left-hand icon; terminal-notifier always shows its own.
//
//   Nudge.app/Contents/MacOS/Nudge --title T --message M
//       [--subtitle S] [--url U] [--image PNG] [--group G] [--thread T]
//       [--action ID=LABEL]... [--env KEY=VALUE]... [--avatar PNG [--sender NAME]]
//   Nudge.app/Contents/MacOS/Nudge --authorize
//
// Posting exits once the notification is added. The request's identifier
// is the group, so a later post with the same group replaces it in place.
// The thread (default: the group) stacks posts in Notification Center.
// When the user clicks one, macOS launches the app again with no
// arguments and hands the delegate the response: it opens the url and
// exits.
//
// Each --action adds a button. A click on one re-reads actions.json and
// runs that id's command, detached, with each --env pair and NUDGE_ACTION
// in its environment. The command only ever comes from that local file at
// click time, never from the notification, and the caller's values only
// ever reach it as env vars.
//
// --avatar makes it a communication notification: an incoming message from
// --sender (default: the title) whose picture is the avatar, which macOS
// draws as the main icon with the app's own icon as a badge. That needs
// the com.apple.developer.usernotifications.communication entitlement
// (build.sh signs with it when a provisioning profile is present); without
// it, or on any error, the notification posts as a plain one. macOS shows
// only the sender and the body of such a notification, so the title and
// subtitle move to the body's first line. Exit status: 0 posted, 2 not allowed, 3 failed, 64 usage.

import AppKit
import Intents
import UserNotifications

struct Post {
    var title = "", subtitle = "", message = "", url = "", image = "", group = "", thread = ""
    var avatar = "", sender = ""
    var actions: [(id: String, label: String)] = []
    var context: [String: String] = [:]  // --env: env var name -> value
}

// $XDG_CONFIG_HOME/nudge/actions.json. Callers that pick buttons from it
// (gitlab-notify) resolve the same path.
func actionsPath() -> String {
    let env = ProcessInfo.processInfo.environment
    let base = env["XDG_CONFIG_HOME"].flatMap { $0.isEmpty ? nil : $0 }
        ?? (NSHomeDirectory() as NSString).appendingPathComponent(".config")
    return (base as NSString).appendingPathComponent("nudge/actions.json")
}

enum Mode {
    case post(Post)
    case authorize
    case launched  // by macOS, for a click
}

func warn(_ msg: String) {
    FileHandle.standardError.write(("nudge: " + msg + "\n").data(using: .utf8)!)
}

func fail(_ code: Int32, _ msg: String) -> Never {
    FileHandle.standardError.write(("nudge: " + msg + "\n").data(using: .utf8)!)
    exit(code)
}

func parse(_ args: [String]) -> Mode {
    if args.isEmpty { return .launched }
    if args == ["--authorize"] { return .authorize }
    var p = Post()
    var i = 0
    while i < args.count {
        guard i + 1 < args.count else { fail(64, "missing value for \(args[i])") }
        let v = args[i + 1]
        switch args[i] {
        case "--title": p.title = v
        case "--subtitle": p.subtitle = v
        case "--message": p.message = v
        case "--url": p.url = v
        case "--image": p.image = v
        case "--group": p.group = v
        case "--thread": p.thread = v
        case "--avatar": p.avatar = v
        case "--sender": p.sender = v
        case "--action":
            guard let eq = v.firstIndex(of: "="), eq != v.startIndex else {
                fail(64, "--action wants ID=LABEL")
            }
            p.actions.append((String(v[..<eq]), String(v[v.index(after: eq)...])))
        case "--env":
            guard let eq = v.firstIndex(of: "="),
                  v[..<eq].range(of: "^[A-Za-z_][A-Za-z0-9_]*$", options: .regularExpression) != nil else {
                fail(64, "--env wants KEY=VALUE")
            }
            p.context[String(v[..<eq])] = String(v[v.index(after: eq)...])
        default: fail(64, "unknown argument \(args[i])")
        }
        i += 2
    }
    if p.title.isEmpty && p.message.isEmpty { fail(64, "need --title or --message") }
    return .post(p)
}

// Older LaunchServices passes a -psn_ argument on launch; it isn't ours.
let args = Array(CommandLine.arguments.dropFirst()).filter { !$0.hasPrefix("-psn_") }
let mode = parse(args)
let center = UNUserNotificationCenter.current()

final class Delegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    // The delegate must be set before launch finishes, or a click that
    // launched us is never delivered.
    func applicationWillFinishLaunching(_ note: Notification) {
        center.delegate = self
    }

    func applicationDidFinishLaunching(_ note: Notification) {
        switch mode {
        case .post(let p):
            // A first run waits on the permission prompt; the script's own
            // timeout is longer than this.
            exitAfter(8, code: 3, "timed out (waiting on the notification permission prompt?)")
            authorized { self.add(p) }
        case .authorize:
            authorized { exit(0) }
        case .launched:
            // Launched for a click: the response arrives right after launch.
            // Launched by hand: nothing arrives.
            exitAfter(5, code: 0, nil)
        }
    }

    func authorized(_ then: @escaping () -> Void) {
        center.getNotificationSettings { s in
            switch s.authorizationStatus {
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound]) { ok, err in
                    if ok { then() } else { fail(2, "notifications not allowed: \(err?.localizedDescription ?? "denied")") }
                }
            case .denied:
                fail(2, "notifications are off for Nudge (System Settings > Notifications)")
            default:
                then()
            }
        }
    }

    func add(_ p: Post) {
        let c = UNMutableNotificationContent()
        c.title = p.title
        c.subtitle = p.subtitle
        c.body = p.message
        var info: [String: Any] = [:]
        if !p.url.isEmpty { info["url"] = p.url }
        if !p.context.isEmpty { info["context"] = p.context }
        c.userInfo = info
        let thread = p.thread.isEmpty ? p.group : p.thread
        if !thread.isEmpty { c.threadIdentifier = thread }
        if !p.image.isEmpty {
            // Adding an attachment moves its file into the notification
            // store, so hand it a copy, never the caller's file.
            do {
                let src = URL(fileURLWithPath: p.image)
                let tmp = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension(src.pathExtension.isEmpty ? "png" : src.pathExtension)
                try FileManager.default.copyItem(at: src, to: tmp)
                c.attachments = [try UNNotificationAttachment(identifier: "image", url: tmp)]
            } catch {
                FileHandle.standardError.write("nudge: image skipped: \(error.localizedDescription)\n".data(using: .utf8)!)
            }
        }
        let id = p.group.isEmpty ? UUID().uuidString : p.group
        let post = {
            self.communicate(c, p) { content in
                center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil)) { err in
                    if let err { fail(3, "post failed: \(err.localizedDescription)") }
                    // Linger so a banner shown while we're frontmost-eligible
                    // (willPresent below) isn't cut off by our exit.
                    self.exitAfter(0.5, code: 0, nil)
                }
            }
        }
        if p.actions.isEmpty { return post() }
        // One category per set of buttons. Categories are app-wide and
        // setNotificationCategories replaces them all, so merge: notifications
        // already up keep their buttons.
        let cat = UNNotificationCategory(
            identifier: "nudge:" + p.actions.map { "\($0.id)=\($0.label)" }.joined(separator: "\u{1f}"),
            actions: p.actions.map { UNNotificationAction(identifier: $0.id, title: $0.label, options: []) },
            intentIdentifiers: [], options: [])
        c.categoryIdentifier = cat.identifier
        center.getNotificationCategories { have in
            center.setNotificationCategories(have.filter { $0.identifier != cat.identifier }.union([cat]))
            post()
        }
    }

    // --avatar: rewrite the content as an incoming message from the sender,
    // whose picture macOS shows as the main icon. Any failure posts `c` as is.
    func communicate(_ c: UNMutableNotificationContent, _ p: Post,
                     _ then: @escaping (UNNotificationContent) -> Void) {
        guard !p.avatar.isEmpty else { return then(c) }
        guard let data = FileManager.default.contents(atPath: p.avatar) else {
            warn("avatar \(p.avatar) unreadable; posting without it")
            return then(c)
        }
        let name = p.sender.isEmpty ? p.title : p.sender
        // A message notification shows only the sender and the body, so the
        // title and subtitle (when they say more than the name) lead the body.
        let head = [p.title == name ? "" : p.title, p.subtitle].filter { !$0.isEmpty }
        if !head.isEmpty {
            c.body = head.joined(separator: " · ") + (c.body.isEmpty ? "" : "\n" + c.body)
        }
        let sender = INPerson(personHandle: INPersonHandle(value: name, type: .unknown),
                              nameComponents: nil, displayName: name, image: INImage(imageData: data),
                              contactIdentifier: nil, customIdentifier: name)
        let intent = INSendMessageIntent(recipients: nil, outgoingMessageType: .outgoingMessageText,
                                         content: c.body, speakableGroupName: nil,
                                         conversationIdentifier: c.threadIdentifier, serviceName: nil,
                                         sender: sender, attachments: nil)
        let interaction = INInteraction(intent: intent, response: nil)
        interaction.direction = .incoming
        interaction.donate { err in
            if let err { warn("donating the message failed: \(err.localizedDescription)") }
            do {
                then(try c.updating(from: intent))
            } catch {
                warn("avatar skipped: \(error.localizedDescription)")
                then(c)
            }
        }
    }

    // We're running when our own notification is posted, which macOS
    // treats as the app being in the foreground: ask for the banner anyway.
    func userNotificationCenter(_ c: UNUserNotificationCenter, willPresent n: UNNotification,
                                withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void) {
        done([.banner, .list])
    }

    func userNotificationCenter(_ c: UNUserNotificationCenter, didReceive r: UNNotificationResponse,
                                withCompletionHandler done: @escaping () -> Void) {
        let info = r.notification.request.content.userInfo
        switch r.actionIdentifier {
        case UNNotificationDefaultActionIdentifier:
            if let s = info["url"] as? String, let url = URL(string: s) {
                NSWorkspace.shared.open(url)
            }
        case UNNotificationDismissActionIdentifier:
            break
        case let id:
            runAction(id, context: info["context"] as? [String: String] ?? [:])
        }
        done()
        exitAfter(0.2, code: 0, nil)
    }

    // Launched by LaunchServices, so stderr goes nowhere: NSLog reaches the
    // unified log (`log show --predicate 'process == "Nudge"'`).
    func runAction(_ id: String, context: [String: String]) {
        let path = actionsPath()
        guard let data = FileManager.default.contents(atPath: path),
              let conf = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let action = conf[id] as? [String: Any] else {
            NSLog("nudge: action %@ not found in %@", id, path)
            return
        }
        guard let argv = action["command"] as? [String], let exe = argv.first, exe.hasPrefix("/") else {
            NSLog("nudge: action %@: command must be an argv list starting with an absolute path", id)
            return
        }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: exe)
        proc.arguments = Array(argv.dropFirst())
        var env = ProcessInfo.processInfo.environment
        for (k, v) in context { env[k] = v }
        env["NUDGE_ACTION"] = id
        proc.environment = env
        proc.currentDirectoryURL = URL(fileURLWithPath: NSHomeDirectory())
        proc.standardInput = FileHandle.nullDevice
        // The command's output, for debugging it.
        let logPath = (NSHomeDirectory() as NSString).appendingPathComponent("Library/Logs/nudge-actions.log")
        if !FileManager.default.fileExists(atPath: logPath) {
            FileManager.default.createFile(atPath: logPath, contents: nil)
        }
        let out = FileHandle(forWritingAtPath: logPath) ?? FileHandle.nullDevice
        out.seekToEndOfFile()
        proc.standardOutput = out
        proc.standardError = out
        do {
            // We exit right after; the command carries on without us.
            try proc.run()
        } catch {
            NSLog("nudge: action %@: %@ failed: %@", id, exe, error.localizedDescription)
        }
    }

    func exitAfter(_ secs: Double, code: Int32, _ msg: String?) {
        DispatchQueue.main.asyncAfter(deadline: .now() + secs) {
            if let msg { fail(code, msg) }
            exit(code)
        }
    }
}

let app = NSApplication.shared
let delegate = Delegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
