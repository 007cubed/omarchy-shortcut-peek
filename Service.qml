import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "Promoter.js" as Promoter

// Shortcut Peek for Omarchy.
//
// When you start something from the Omarchy shell (menu, dock, app grid)
// that already has a keybinding, show the shortcut in a small themed toast.
//
// The shell, not the window, is the evidence. Everything uwsm launches gets a
// scope under app-graphical.slice, and a scope's first process carries the
// environment of whoever started it: the shell marks its own with QS_*
// variables (omarchy-launch-shell) that Hyprland's environment never has.
// bin/launch-watch reports each new scope as "shell" or "other", so a launch
// from a keybinding never triggers a toast, whatever the timing. The next
// window after a shell launch is matched against your binds.
//
// What has no scope of its own still needs the menu as the cue:
//   - scripts (screenshot, color picker, lock): a young process carrying the
//     shell marker, found by a short process scan after the menu closes;
//   - shell layers (emojis, clipboard): no trace survives, so these rely on
//     the menu having closed just before.
//
// Bindings are read from this machine, not from Omarchy's defaults, via
// bin/keybinds, which reuses the resolver behind SUPER + K.
Item {
  id: service

  // Injected by omarchy-shell.
  property var shell: null
  property var manifest: null
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")

  readonly property string home: Quickshell.env("HOME")
  readonly property string pluginId: manifest && manifest.id ? String(manifest.id) : "guykawaii.shortcut-peek"
  readonly property string pluginDir: String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "").replace(/\/$/, "")
  readonly property string statePath: home + "/.local/state/omarchy/shortcut-peek.json"

  // Settings, inline on this plugin's entry in ~/.config/omarchy/shell.json:
  //   { "id": "guykawaii.shortcut-peek", "duration": 3500, "position": "bottom-right", "window": 3000, "showCount": true }
  // position: top-left | top-center | top-right | bottom-left | bottom-center | bottom-right
  property int duration: 3500
  property string position: "bottom-right"
  readonly property var positions: ["top-left", "top-center", "top-right", "bottom-left", "bottom-center", "bottom-right"]
  property int window: 3000
  property bool showCount: true

  property var binds: []
  property var counts: ({})
  property double armedAt: 0
  property int psRuns: 0

  // Launch origin, see the header comment.
  // Where uwsm puts app scopes: .../user@UID.service/app.slice/app-graphical.slice
  readonly property string appSlice: {
    var m = /\/run\/user\/(\d+)/.exec(Quickshell.env("XDG_RUNTIME_DIR") || "")
    return m ? "/sys/fs/cgroup/user.slice/user-" + m[1] + ".slice/user@" + m[1] + ".service/app.slice/app-graphical.slice" : ""
  }
  // An environment variable only shell-started processes carry. Read off this
  // very process, so if omarchy-launch-shell stops setting it we notice and
  // fall back to the time window instead of never promoting a script again.
  readonly property string shellMarker: {
    var names = ["QS_NO_RELOAD_POPUP", "QS_DISABLE_FILE_WATCHER"]
    for (var i = 0; i < names.length; i++) if (Quickshell.env(names[i])) return names[i]
    return ""
  }
  property bool launchWatchOk: false
  property int launchWatchRetries: 0
  // When the shell last started an app scope; cleared by the first window
  // after it, by a launch from anywhere else, and by a toast.
  property double shellLaunchAt: 0
  // Slow apps (Electron, Steam) take a while to map their first window. The
  // origin is already proven, so this only bounds how long to wait for it.
  readonly property int launchWindow: 10000

  function applySettings(raw) {
    try {
      var cfg = JSON.parse(raw || "{}")
      var list = Array.isArray(cfg.plugins) ? cfg.plugins : []
      for (var i = 0; i < list.length; i++) {
        var e = list[i]
        if (!e || e.id !== service.pluginId) continue
        if (e.duration !== undefined) duration = Math.max(500, parseInt(e.duration, 10) || 3500)
        if (e.position !== undefined) {
          var pos = String(e.position)
          if (pos === "top" || pos === "bottom") pos += "-center"
          if (positions.indexOf(pos) !== -1) position = pos
        }
        if (e.window !== undefined) window = Math.max(500, parseInt(e.window, 10) || 3000)
        if (e.showCount !== undefined) showCount = e.showCount !== false
        return
      }
    } catch (err) {}
  }

  function loadBinds(raw) {
    try {
      binds = Promoter.prepare(JSON.parse(raw || "{}"))
    } catch (err) {
      console.warn("shortcut-peek: could not parse keybinds:", err)
    }
  }

  function loadCounts(raw) {
    try { counts = JSON.parse(raw || "{}") || {} } catch (err) { counts = {} }
  }

  function bump(combo) {
    var next = {}
    for (var k in counts) next[k] = counts[k]
    next[combo] = (next[combo] || 0) + 1
    counts = next
    stateFile.setText(JSON.stringify(counts, null, 2) + "\n")
    return next[combo]
  }

  function arm() {
    armedAt = Date.now()
    psRuns = 0
    psTimer.restart()
  }

  function armed() { return armedAt > 0 && Date.now() - armedAt <= window }

  function disarm() {
    armedAt = 0
    psTimer.stop()
  }

  function onLaunch(line) {
    var launch = Promoter.parseLaunch(line)
    if (!launch) return
    shellLaunchAt = launch.shell ? Date.now() : 0
  }

  // Is this new window the result of something the shell just started?
  // Without the watcher there is no evidence, so fall back to the menu timing.
  function windowFromShell() {
    if (!launchWatchOk) return armed()
    return shellLaunchAt > 0 && Date.now() - shellLaunchAt <= launchWindow
  }

  function promote(bind) {
    disarm()
    shellLaunchAt = 0
    toast.show(bind.combo, bind.description, bump(bind.combo))
  }

  Component.onCompleted: {
    bindsProc.running = true
    if (appSlice && shellMarker) launchWatch.running = true
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      var name = String(event.name)
      var data = String(event.data)
      if (name === "configreloaded") { bindsProc.running = true; return }
      if (name === "closelayer") { if (data === "omarchy-menu") service.arm(); return }
      if (name === "openwindow") {
        if (!service.windowFromShell()) return
        // One window per launch: whatever opens next is not the shell's doing.
        service.shellLaunchAt = 0
        var parts = event.parse(4)
        var cls = parts.length > 2 ? parts[2] : ""
        var entry = cls ? DesktopEntries.heuristicLookup(cls) : null
        var hit = Promoter.matchWindow(service.binds, cls, entry)
        if (hit) service.promote(hit)
        return
      }
      if (!service.armed()) return
      if (name === "openlayer") {
        // The menu reopened (submenu, launcher); wait for what it does next.
        if (data === "omarchy-menu") { service.disarm(); return }
        var layerHit = Promoter.matchLayer(service.binds, data)
        if (layerHit) service.promote(layerHit)
      }
    }
  }

  // Scripts with no window of their own show up only in the process table.
  Timer {
    id: psTimer
    // Short and frequent: a script that execs into another program loses its
    // name within moments, so the first looks count most.
    interval: 150
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      if (!service.armed() || service.psRuns >= 8) { psTimer.stop(); return }
      service.psRuns++
      psProc.running = true
    }
  }

  // Prints "<etimes> <shell|-> <args>" for processes younger than 4s, where
  // "shell" means the process environment carries the shell marker.
  Process {
    id: psProc
    command: ["bash", "-c", [
      "ps -eo etimes=,pid=,args= | while read -r et pid args; do",
      "  [ \"$et\" -le 3 ] || continue",
      "  tag=-",
      "  if [ -n \"$1\" ] && grep -qsz \"^$1=\" \"/proc/$pid/environ\"; then tag=shell; fi",
      "  printf '%s %s %s\\n' \"$et\" \"$tag\" \"$args\"",
      "done"
    ].join("\n"), "ps-scan", service.shellMarker]
    stdout: StdioCollector {
      onStreamFinished: {
        if (!service.armed()) return
        var hit = Promoter.matchProcesses(service.binds, text, 3, service.shellMarker !== "")
        if (hit) service.promote(hit)
      }
    }
  }

  // Scope directories appearing under the app slice, one name per line.
  Process {
    id: launchWatch
    command: ["bash", service.pluginDir + "/bin/launch-watch", service.appSlice, service.shellMarker]
    onStarted: { service.launchWatchOk = true; service.launchWatchRetries = 0 }
    onExited: {
      service.launchWatchOk = false
      if (service.launchWatchRetries++ < 5) launchWatchRetry.restart()
      else console.warn("shortcut-peek: launch watcher gave up; falling back to the menu timing alone")
    }
    stdout: SplitParser {
      onRead: function(line) { service.onLaunch(line) }
    }
    stderr: StdioCollector { onStreamFinished: if (text.length) console.warn("shortcut-peek launch-watch:", text) }
  }

  Timer {
    id: launchWatchRetry
    interval: 5000
    onTriggered: launchWatch.running = true
  }

  Process {
    id: bindsProc
    command: ["bash", service.pluginDir + "/bin/keybinds"]
    stdout: StdioCollector { onStreamFinished: service.loadBinds(text) }
    stderr: StdioCollector { onStreamFinished: if (text.length) console.warn("shortcut-peek keybinds:", text) }
  }

  FileView {
    id: shellConfig
    path: service.home + "/.config/omarchy/shell.json"
    watchChanges: true
    printErrors: false
    onLoaded: service.applySettings(text())
    onFileChanged: reload()
  }

  FileView {
    id: stateFile
    path: service.statePath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: service.loadCounts(text())
  }

  Toast {
    id: toast
    shell: service.shell
    duration: service.duration
    position: service.position
    showCount: service.showCount
  }

  IpcHandler {
    target: "shortcut-peek"
    function ping(): string { return "ok" }
    function reload(): string { bindsProc.running = true; return "ok" }
    function show(combo: string, description: string): string { toast.show(combo, description, 0); return "ok" }
    function hide(): string { toast.hide(); return "ok" }
    function stats(): string { return JSON.stringify(service.counts) }
    function state(): string {
      return JSON.stringify({
        armed: service.armed(),
        launchWatch: service.launchWatchOk,
        appSlice: service.appSlice,
        shellMarker: service.shellMarker,
        msSinceShellLaunch: service.shellLaunchAt ? Date.now() - service.shellLaunchAt : null
      })
    }
    function resolved(): string {
      var out = []
      for (var i = 0; i < service.binds.length; i++) {
        var b = service.binds[i]
        if (b.sig && b.sig.kind !== "menu") out.push({ combo: b.combo, description: b.description, sig: b.sig })
      }
      return JSON.stringify(out)
    }
  }
}
