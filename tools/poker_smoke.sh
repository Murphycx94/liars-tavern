#!/usr/bin/env bash
# 德州 / 21 点无头联机冒烟(规格 §8):1 个房主 + 直连 bot + 局域网发现 bot 开局;房主开始第 1 手后再来一个发现 bot(验证对局中可加入)。
# 房主打到第 HANDS 手(局)后散局。用法:MODE=holdem|short_deck|blackjack tools/poker_smoke.sh
# 通过条件:4 个进程都以 0 退出、都打印 SESSION_OVER、迟到者至少被发到一手牌、德州房主 net_sum=0(21 点和庄家对赌,不检查)、
#          每个日志都收到另外 3 人的视线与脖子(GAZE peers=3 necks=3)与快捷对话(QUIPS heard=3)、没有脚本错误。
set -u

GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
MODE="${MODE:-holdem}"
HANDS="${HANDS:-6}"
CAP_SECONDS="${CAP_SECONDS:-300}"
SPEED="${SPEED:-4}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOG_DIR="$(mktemp -d "${TMPDIR:-/tmp}/poker_smoke.XXXXXX")"
PEERS=3   # 每个进程应看到的其他人数

run_capped() {
	# macOS 没有 timeout 命令,用 perl alarm 兜底
	perl -e 'alarm shift; exec @ARGV' "$CAP_SECONDS" "$@"
}

COMMON=(--headless --path "$ROOT" -- --bot --fast="$SPEED" --quit-after-match)
# 每次运行用独立的游戏端口与房名:同机并行跑多份冒烟时,直连与发现都只会进自己的房间
PORT="${PORT:-$((47830 + RANDOM % 150))}"
ROOM="德州冒烟$$"
START_MARK="HAND_STARTED hand=1"
if [ "$MODE" = "blackjack" ]; then
	ROOM="21点冒烟$$"
	START_MARK="ROUND_STARTED round=1"
fi

run_capped "$GODOT" "${COMMON[@]}" --autohost=3 --mode="$MODE" --hands="$HANDS" --port="$PORT" --room="$ROOM" \
	--name=房主 >"$LOG_DIR/host.log" 2>&1 &
HOST=$!
sleep 2
run_capped "$GODOT" "${COMMON[@]}" --discover="$ROOM" --name=发现 >"$LOG_DIR/discover.log" 2>&1 &
DISCOVER=$!
run_capped "$GODOT" "${COMMON[@]}" --autojoin="127.0.0.1:$PORT" --name=直连 >"$LOG_DIR/direct.log" 2>&1 &
DIRECT=$!

# 等房主开始第 1 手再放迟到者进来(房主提前退出或超时就不等了)
waited=0
until grep -q "$START_MARK" "$LOG_DIR/host.log" 2>/dev/null; do
	if ! kill -0 "$HOST" 2>/dev/null || [ "$waited" -ge "$CAP_SECONDS" ]; then
		break
	fi
	sleep 1
	waited=$((waited + 1))
done
run_capped "$GODOT" "${COMMON[@]}" --discover="$ROOM" --name=迟到 >"$LOG_DIR/late.log" 2>&1 &
LATE=$!

status=0
for pair in "host:$HOST" "discover:$DISCOVER" "direct:$DIRECT" "late:$LATE"; do
	name="${pair%%:*}"
	pid="${pair##*:}"
	if wait "$pid"; then code=0; else code=$?; fi
	log="$LOG_DIR/$name.log"
	# 脚本错误与 push_error 打出的引擎错误行都算失败
	errors=$(grep -c "SCRIPT ERROR\|^ERROR:" "$log" || true)
	problems=""
	[ "$code" -ne 0 ] && problems="$problems exit=$code"
	[ "$errors" -ne 0 ] && problems="$problems script_errors=$errors"
	grep -q "SESSION_OVER" "$log" || problems="$problems no_session_over"
	grep -q "GAZE peers=$PEERS necks=$PEERS" "$log" || problems="$problems gaze"
	grep -q "QUIPS heard=$PEERS" "$log" || problems="$problems quips"
	if [ "$name" = "host" ] && [ "$MODE" != "blackjack" ] && ! grep -q "net_sum=0$" "$log"; then
		problems="$problems net_sum"
	fi
	if [ "$name" = "late" ] && ! grep -q "SESSION_OVER hands_dealt=[1-9]" "$log"; then
		problems="$problems late_not_dealt"
	fi
	if [ -n "$problems" ]; then
		echo "FAIL $name ($problems) — 日志:$log"
		grep -A3 "SCRIPT ERROR\|FAIL" "$log" | head -20
		status=1
	else
		echo "ok   $name — $(grep -m1 SESSION_OVER "$log" | sed 's/.*SESSION_OVER //') · $(grep -m1 -o "GAZE peers=[0-9]* necks=[0-9]*" "$log") · $(grep -m1 -o "QUIPS heard=[0-9]*" "$log")$(grep -m1 -o " net_sum=-*[0-9]*" "$log")"
	fi
done
# 每端实际建出来的酒客形象必须一致(房主分配的形象要在每个人的画面上都对得上)
patron_lines=()
for name in host discover direct late; do
	patron_lines+=("$(grep '\[debug\] patrons' "$LOG_DIR/$name.log" | tail -1)")
done
if [ -z "${patron_lines[0]}" ] || [ "$(printf '%s\n' "${patron_lines[@]}" | sort -u | wc -l | tr -d ' ')" -ne 1 ]; then
	echo "FAIL patrons — 各端看到的酒客形象不一致:"
	printf '  %s\n' "${patron_lines[@]}"
	status=1
else
	echo "ok   patrons — ${patron_lines[0]}"
fi
[ "$status" -eq 0 ] && echo "联机冒烟($MODE)通过(日志:$LOG_DIR)"
exit "$status"
