#!/bin/sh
# End to end test of the CLI, the socket and the app, without any window.
# The app runs in test mode (HUMANPLS_AUTOANSWER) with its own data folder, so your real history is not touched.
set -u
cd "$(dirname "$0")/.."
BIN="${BIN:-.build/debug/humanpls}"
HOME_DIR="$(mktemp -d)"
export HUMANPLS_HOME="$HOME_DIR" HUMANPLS_SOCKET="$HOME_DIR/h.sock"
FILES="$HOME_DIR/files"; mkdir -p "$FILES"
printf 'x' > "$FILES/a.png"; printf 'x' > "$FILES/b.wav"; printf '# hi' > "$FILES/n.md"
pass=0; fail=0
check() { # name, expected, actual
  if [ "$2" = "$3" ]; then pass=$((pass+1)); echo "ok   $1"; else fail=$((fail+1)); echo "FAIL $1"; echo "  want: $2"; echo "  got:  $3"; fi
}

out=$(HUMANPLS_AUTOANSWER=send "$BIN" pick --id narrator --wait "*$FILES/a.png::Wide" "$FILES/b.wav::Low")
check "pick --wait returns the pre-picked recommended option" "[narrator] picked: A \"Wide\" (a.png)" "$out"

out=$(HUMANPLS_AUTOANSWER=send "$BIN" pick --id ep2 --wait --section Name "text:Aung" "*text:Maung" --section Notes "$FILES/n.md" )
check "several questions" "[ep2]
Name: B \"Maung\"
Notes: no pick" "$out"

HUMANPLS_AUTOANSWER=cancel "$BIN" pick --id c1 --wait "text:Yes" "text:No" >/dev/null 2>&1; code=$?
check "cancelled popup exits with 3" "3" "$code"

out=$(HUMANPLS_AUTOANSWER=copy "$BIN" pick --id c2 --wait "*text:Yes" "text:No")
check "copy only still prints the answer with --wait" "[c2] picked: A \"Yes\"" "$out"

out=$(HUMANPLS_AUTOANSWER=send "$BIN" pick --id nowait "text:Yes")
check "without --wait it only reports that it opened" "opened: nowait (1 items)" "$out"

"$BIN" pick --id bad "$FILES/missing.png" >/dev/null 2>&1; code=$?
check "missing file is an error (exit 2)" "2" "$code"

out=$("$BIN" pick --id d --dump-job "*text:Yes" | grep -c '"selected" : true')
check "--dump-job prints the job and opens nothing" "1" "$out"

out=$(HUMANPLS_AUTOANSWER=send "$BIN" show --id look --wait "$FILES")
check "show --wait returns the id" "[look]" "$out"

count=$("$BIN" list | wc -l | tr -d ' ')
check "history lists the 6 popups that opened" "6" "$count"

out=$(HUMANPLS_AUTOANSWER=send "$BIN" reopen narrator)
check "reopen from history" "reopened narrator" "$out"

"$BIN" quit >/dev/null 2>&1
sleep 0.5
if [ -S "$HUMANPLS_SOCKET" ]; then fail=$((fail+1)); echo "FAIL socket removed after quit"; else pass=$((pass+1)); echo "ok   socket removed after quit"; fi
rm -rf "$HOME_DIR"
echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
