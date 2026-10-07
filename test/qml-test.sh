#!/bin/bash

set -euo pipefail

# Compiles the QML files with the modules of the installed Omarchy Shell.
# The shell compiles Panel.qml only when the panel opens. Thus a reload of the
# plugins does not show an error in it.

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
shell="${OMARCHY_PATH:-$HOME/.local/share/omarchy}/shell"

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

pass() {
  printf 'ok - %s\n' "$1"
}

if ! command -v qs >/dev/null || [[ ! -d $shell/Commons ]]; then
  pass "the QML files compile # SKIP no Omarchy Shell"
  exit 0
fi

tmp=$(mktemp -d)
pid=""
trap 'if [[ -n $pid ]]; then kill "$pid" 2>/dev/null || true; fi; rm -rf "$tmp"' EXIT
mkdir "$tmp/config"
# The imports qs.Commons and qs.Ui resolve in the folder of the configuration.
for dir in "$shell"/*/; do
  ln -s "$dir" "$tmp/config/$(basename "$dir")"
done

# The configuration opens no window. It writes one line for each file.
cat >"$tmp/config/shell.qml" <<'QML'
import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
  FileView {
    id: result
    path: Quickshell.env("QML_TEST_RESULT")
    atomicWrites: true
  }

  Component.onCompleted: {
    var files = Quickshell.env("QML_TEST_FILES").split(":")
    var lines = []
    for (var i = 0; i < files.length; i++) {
      var component = Qt.createComponent("file://" + files[i], Component.PreferSynchronous)
      var status = component.status === Component.Ready ? "ok" : "error"
      lines.push(status + "\t" + files[i] + "\t" + component.errorString().replace(/\n/g, " "))
    }
    result.setText(lines.join("\n") + "\n")
  }
}
QML
printf 'import QtQuick\nItem { NoSuchType {} }\n' >"$tmp/Broken.qml"

QML_TEST_RESULT="$tmp/result" QML_TEST_FILES="$root/Service.qml:$root/BarWidget.qml:$root/Panel.qml:$root/Detail.qml:$root/KeyHints.qml:$tmp/Broken.qml" \
  qs -p "$tmp/config" >/dev/null 2>&1 &
pid=$!
for _ in $(seq 100); do
  [[ -s $tmp/result ]] && break
  sleep 0.1
done
kill "$pid" 2>/dev/null || true
wait "$pid" 2>/dev/null || true
pid=""

[[ -s $tmp/result ]] || fail "Quickshell compiles the QML files"
grep -q "^error	$tmp/Broken.qml	.*NoSuchType" "$tmp/result" || fail "the check finds an error in a broken file"
for file in Service.qml BarWidget.qml Panel.qml Detail.qml KeyHints.qml; do
  line=$(grep -F "	$root/$file	" "$tmp/result" || true)
  [[ $line == ok* ]] || fail "$file compiles: ${line##*	}"
done
pass "the QML files compile with the modules of the shell"
