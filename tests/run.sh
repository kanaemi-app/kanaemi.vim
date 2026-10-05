#!/bin/sh
# Runs tests/test.vim in Vim and in Neovim, each against a fake server of
# its own.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
status=0

run() {
  name=$1
  shift
  portfile=$(mktemp)
  : >"$portfile"
  python3 "$root/tests/fake_server.py" "$portfile" &
  server=$!
  while [ ! -s "$portfile" ]; do
    perl -e 'select undef, undef, undef, 0.05'
  done
  read -r port admin <"$portfile"
  rm -f "$portfile"
  echo "== $name"
  KANAEMI_TEST_PORT=$port KANAEMI_TEST_ADMIN=$admin "$@" || status=1
  kill "$server"
}

if command -v vim >/dev/null; then
  run vim vim -Nu NONE -i NONE -n -es -S "$root/tests/test.vim"
fi
if command -v nvim >/dev/null; then
  run nvim nvim --clean --headless -n -S "$root/tests/test.vim"
fi
exit $status
