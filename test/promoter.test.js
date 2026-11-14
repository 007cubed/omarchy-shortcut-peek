// Plain-node tests for Promoter.js: node test/promoter.test.js
const assert = require("assert")
const fs = require("fs")
const path = require("path")

const src = fs.readFileSync(path.join(__dirname, "..", "Promoter.js"), "utf8").replace(/^\.pragma.*$/m, "")
const P = new Function(src + "\nreturn { prepare, matchWindow, matchLayer, matchProcesses, parseLaunch, chips, signatureForCommand }")()

const binds = P.prepare({
  binds: [
    { combo: "SUPER + RETURN", description: "Terminal", dispatcher: "exec", arg: "omarchy-launch-terminal" },
    { combo: "SUPER SHIFT + RETURN", description: "Browser", dispatcher: "exec", arg: "omarchy-launch-browser" },
    { combo: "SUPER SHIFT + F", description: "File manager", dispatcher: "exec", arg: "omarchy-launch-nautilus" },
    { combo: "SUPER SHIFT + T", description: "Activity", dispatcher: "exec", arg: "omarchy-launch-or-focus-tui btop" },
    { combo: "SUPER SHIFT + R", description: "Orca", dispatcher: "exec", arg: "omarchy-launch-or-focus '^orca$' 'uwsm-app -- gtk-launch orca'" },
    { combo: "SUPER + PRINT", description: "Color picker", dispatcher: "exec", arg: "pkill hyprpicker || hyprpicker -a" },
    { combo: "SUPER SHIFT + X", description: "X", dispatcher: "exec", arg: "omarchy-launch-webapp https://x.com/" },
    { combo: "PRINT", description: "Screenshot", dispatcher: "exec", arg: "omarchy-cmd-screenshot" },
    { combo: "SUPER CTRL + E", description: "Emoji picker", dispatcher: "exec", arg: "omarchy-shell omarchy.emojis toggle" },
    { combo: "XF86Calculator", description: "Calculator", dispatcher: "exec", arg: "omacalc" },
    { combo: "SUPER SHIFT + Q", description: "Calculator", dispatcher: "exec", arg: "omacalc" },
  ],
  defaults: { browser: "brave-origin", editor: "nvim", terminal: "foot" },
})

const combo = (hit) => (hit ? hit.combo : null)
const tests = {
  "terminal window matches the default terminal": () =>
    assert.strictEqual(combo(P.matchWindow(binds, "foot", null)), "SUPER + RETURN"),
  "browser window matches the resolved browser": () =>
    assert.strictEqual(combo(P.matchWindow(binds, "brave-origin", null)), "SUPER SHIFT + RETURN"),
  "nautilus window matches through its desktop entry": () =>
    assert.strictEqual(combo(P.matchWindow(binds, "org.gnome.Nautilus", { id: "org.gnome.Nautilus.desktop", command: ["nautilus", "--new-window"] })), "SUPER SHIFT + F"),
  "TUI window matches by app id": () =>
    assert.strictEqual(combo(P.matchWindow(binds, "org.omarchy.btop", null)), "SUPER SHIFT + T"),
  "gtk-launch inside launch-or-focus resolves to the desktop id": () =>
    assert.strictEqual(combo(P.matchWindow(binds, "orca", null)), "SUPER SHIFT + R"),
  "web app window matches host": () =>
    assert.strictEqual(combo(P.matchWindow(binds, "brave-x.com__-Default", null)), "SUPER SHIFT + X"),
  "media key never wins over a real shortcut": () =>
    assert.strictEqual(combo(P.matchWindow(binds, "omacalc", null)), "SUPER SHIFT + Q"),
  "unbound window gives nothing": () =>
    assert.strictEqual(P.matchWindow(binds, "steam", null), null),
  "command list keeps its last command": () =>
    assert.deepStrictEqual(P.signatureForCommand("pkill hyprpicker || hyprpicker -a", {}), { kind: "app", value: "hyprpicker", cmd: "hyprpicker" }),
  "windowless tool matches its shell-started process": () =>
    assert.strictEqual(combo(P.matchProcesses(binds, "0 shell hyprpicker -a\n", 3, true)), "SUPER + PRINT"),
  "script run by bash matches its name": () =>
    assert.strictEqual(combo(P.matchProcesses(binds, "1 shell /bin/bash /usr/share/omarchy/bin/omarchy-cmd-screenshot\n", 3, true)), "PRINT"),
  "processes without the shell marker are ignored": () =>
    assert.strictEqual(P.matchProcesses(binds, "0 - hyprpicker -a\n", 3, true), null),
  "old processes are ignored": () =>
    assert.strictEqual(P.matchProcesses(binds, "9 shell hyprpicker -a\n", 3, true), null),
  "emoji layer matches the shell toggle": () =>
    assert.strictEqual(combo(P.matchLayer(binds, "omarchy-emojis")), "SUPER CTRL + E"),
  "launch lines parse": () => {
    assert.deepStrictEqual(P.parseLaunch("shell\tapp-Hyprland-foot-1.scope\t/usr/bin/foot"), { shell: true, unit: "app-Hyprland-foot-1.scope", cmd: "/usr/bin/foot" })
    assert.deepStrictEqual(P.parseLaunch("other\tapp-Hyprland-foot-2.scope"), { shell: false, unit: "app-Hyprland-foot-2.scope", cmd: "" })
    assert.strictEqual(P.parseLaunch("garbage"), null)
  },
  "chips split modifiers and key": () =>
    assert.deepStrictEqual(P.chips("SUPER SHIFT + RETURN"), ["SUPER", "SHIFT", "RETURN"]),
}

let failed = 0
for (const [name, fn] of Object.entries(tests)) {
  try { fn(); console.log("ok   " + name) } catch (err) { failed++; console.log("FAIL " + name + "\n     " + err.message) }
}
process.exit(failed ? 1 : 0)
