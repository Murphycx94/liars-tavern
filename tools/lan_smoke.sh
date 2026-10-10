#!/usr/bin/env bash
# 无头联机冒烟:1 个房主 + 2 个 bot 客户端(一个走局域网发现,一个直连 127.0.0.1)跑完整局。
# 通过条件:三个进程都以 0 退出、都收到 MATCH_OVER、都收到另外两人的视线与脖子同步和快捷对话(QUIPS heard=2)、
# 都收到三个人各丢的一个番茄和各说的一句快捷语(BANTER tomatoes=3 said=3)、日志里没有脚本错误;
# 三人都要企鹅(--species=penguin,2026-10-10 新加的下标 9,顺带验证新形象过网络):三个日志最后一条 [debug] species 完全一致,房主是 penguin,
# 另外两人各不相同且不是 penguin(先到先得,被占时房主给空着的)。
# 接着再跑一局炸弹猫(--mode=bomb_cat,同样 1 房主 + 发现 + 直连,机器人走牌桌的真实入口出牌、不行!、摸牌、塞回、给牌):
# 三个进程都以 0 退出、都打到 MATCH_OVER、三端的胜者一致、都收到另外两人的九宫格快捷对话(QUIPS heard=2)、日志里没有脚本错误。
# 最后再跑一局吹牛骰子(--mode=liars_dice,同样 1 房主 + 发现 + 直连,机器人经出价器喊价或「开!」):
# 三个进程都以 0 退出、都打到 MATCH_OVER、三端的胜者一致、都收到另外两人的九宫格快捷对话(QUIPS heard=2)、日志里没有脚本错误。
# 再跑一局斗地主(--mode=dou_dizhu,正好 3 端:1 房主 + 发现 + 直连,机器人走牌桌的真实入口叫分、按提示出牌、不出;
# 房主 --hands=DDZ_HANDS(默认 3)打到第 N 手开始时散局):三个进程都以 0 退出、都打印 SESSION_OVER 与九宫格快捷对话(QUIPS heard=2)、
# 日志里没有脚本错误、房主打完了 N 手(DDZ_HAND_OVER 有 N 条)、三端的结算行(DDZ_RESULTS)完全一致且分数总和为 0。
# SKIP_BOMB_CAT=1 时不跑炸弹猫,SKIP_LIARS_DICE=1 时不跑吹牛骰子,SKIP_DOU_DIZHU=1 时不跑斗地主。
set -u

GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
CAP_SECONDS="${CAP_SECONDS:-240}"
SPEED="${SPEED:-4}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOG_DIR="$(mktemp -d "${TMPDIR:-/tmp}/liars_smoke.XXXXXX")"

run_capped() {
	# macOS 没有 timeout 命令,用 perl alarm 兜底
	perl -e 'alarm shift; exec @ARGV' "$CAP_SECONDS" "$@"
}

COMMON=(--headless --path "$ROOT" -- --bot --fast="$SPEED" --quit-after-match --species=penguin)
# 每次运行用独立的游戏端口与房名:同机并行跑多份冒烟时,直连与发现都只会进自己的房间
PORT="${PORT:-$((47830 + RANDOM % 150))}"
ROOM="冒烟$$"

run_capped "$GODOT" "${COMMON[@]}" --autohost=3 --port="$PORT" --room="$ROOM" --name=房主 >"$LOG_DIR/host.log" 2>&1 &
HOST=$!
sleep 2
run_capped "$GODOT" "${COMMON[@]}" --discover="$ROOM" --name=发现 >"$LOG_DIR/discover.log" 2>&1 &
DISCOVER=$!
run_capped "$GODOT" "${COMMON[@]}" --autojoin="127.0.0.1:$PORT" --name=直连 >"$LOG_DIR/direct.log" 2>&1 &
DIRECT=$!

status=0
for pair in "host:$HOST" "discover:$DISCOVER" "direct:$DIRECT"; do
	name="${pair%%:*}"
	pid="${pair##*:}"
	if wait "$pid"; then code=0; else code=$?; fi
	log="$LOG_DIR/$name.log"
	# 脚本错误与 push_error 打出的引擎错误行都算失败
	errors=$(grep -c "SCRIPT ERROR\|^ERROR:" "$log" || true)
	# 每个进程都应收到另外两人的视线与伸出的脖子(房主直收,客户端经房主转发)
	if [ "$code" -ne 0 ] || ! grep -q "MATCH_OVER" "$log" || [ "$errors" -ne 0 ] || ! grep -q "GAZE peers=2 necks=2" "$log" \
		|| ! grep -q "BANTER tomatoes=3 said=3" "$log" || ! grep -q "QUIPS heard=2" "$log"; then
		echo "FAIL $name (exit=$code, script_errors=$errors) — 日志:$log"
		grep -A3 "SCRIPT ERROR\|FAIL" "$log" | head -20
		status=1
	else
		echo "ok   $name — $(grep -m1 MATCH_OVER "$log") · $(grep -m1 -o "GAZE peers=[0-9]* necks=[0-9]*" "$log") · $(grep -m1 -o "BANTER tomatoes=[0-9]* said=[0-9]*" "$log") · $(grep -m1 -o "QUIPS heard=[0-9]*" "$log")"
	fi
done
# 形象:三端最后一条形象表(开局时的座位表)必须完全一致
species_lines=()
for name in host discover direct; do
	species_lines+=("$(grep '\[debug\] species' "$LOG_DIR/$name.log" | tail -1)")
done
if [ -z "${species_lines[0]}" ] || [ "${species_lines[0]}" != "${species_lines[1]}" ] || [ "${species_lines[0]}" != "${species_lines[2]}" ]; then
	echo "FAIL species — 三端的形象表不一致:"
	printf '  %s\n' "${species_lines[@]}"
	status=1
else
	# 「[debug] species {1: penguin, 123: fox, 456: bear}」→ 每行一个「pid id」
	entries=$(echo "${species_lines[0]}" | sed -e 's/.*{//' -e 's/}.*//' | tr ',' '\n' | sed -e 's/^ *//' -e 's/: / /')
	host_species=$(echo "$entries" | awk '$1 == 1 {print $2}')
	others=$(echo "$entries" | awk '$1 != 1 {print $2}')
	other_count=$(echo "$others" | grep -c . || true)
	unique_count=$(echo "$others" | sort -u | grep -c . || true)
	if [ "$host_species" != "penguin" ] || [ "$other_count" -ne 2 ] || [ "$unique_count" -ne 2 ] \
		|| echo "$others" | grep -qx -e 'penguin' -e '-'; then
		echo "FAIL species — 分配不对:${species_lines[0]}"
		status=1
	else
		echo "ok   species — ${species_lines[0]}"
	fi
fi

# —— 炸弹猫一局 ——
if [ "${SKIP_BOMB_CAT:-0}" != "1" ]; then
	BOMB_PORT=$((PORT + 200))
	BOMB_ROOM="猫窝$$"
	BOMB_COMMON=(--headless --path "$ROOT" -- --bot --fast="$SPEED" --quit-after-match)
	run_capped "$GODOT" "${BOMB_COMMON[@]}" --autohost=3 --mode=bomb_cat --port="$BOMB_PORT" --room="$BOMB_ROOM" --name=猫房主 \
		>"$LOG_DIR/bomb_host.log" 2>&1 &
	BHOST=$!
	sleep 2
	run_capped "$GODOT" "${BOMB_COMMON[@]}" --discover="$BOMB_ROOM" --name=猫发现 >"$LOG_DIR/bomb_discover.log" 2>&1 &
	BDISCOVER=$!
	run_capped "$GODOT" "${BOMB_COMMON[@]}" --autojoin="127.0.0.1:$BOMB_PORT" --name=猫直连 >"$LOG_DIR/bomb_direct.log" 2>&1 &
	BDIRECT=$!
	winners=()
	for pair in "bomb_host:$BHOST" "bomb_discover:$BDISCOVER" "bomb_direct:$BDIRECT"; do
		name="${pair%%:*}"
		pid="${pair##*:}"
		if wait "$pid"; then code=0; else code=$?; fi
		log="$LOG_DIR/$name.log"
		errors=$(grep -c "SCRIPT ERROR" "$log" || true)
		winner=$(grep -m1 -o "MATCH_OVER winner=[0-9]*" "$log" || true)
		winners+=("$winner")
		if [ "$code" -ne 0 ] || [ -z "$winner" ] || [ "$errors" -ne 0 ] || ! grep -q "QUIPS heard=2" "$log"; then
			echo "FAIL $name (exit=$code, script_errors=$errors) — 日志:$log"
			grep -A3 "SCRIPT ERROR\|FAIL" "$log" | head -20
			status=1
		else
			echo "ok   $name — 炸弹猫 $winner · $(grep -m1 -o "QUIPS heard=[0-9]*" "$log")"
		fi
	done
	if [ -z "${winners[0]}" ] || [ "${winners[0]}" != "${winners[1]}" ] || [ "${winners[0]}" != "${winners[2]}" ]; then
		echo "FAIL bomb_cat winner — 三端的胜者不一致:"
		printf '  %s\n' "${winners[@]}"
		status=1
	else
		echo "ok   bomb_cat — 三端胜者一致(${winners[0]})"
	fi
fi
# —— 吹牛骰子一局 ——
if [ "${SKIP_LIARS_DICE:-0}" != "1" ]; then
	DICE_PORT=$((PORT + 400))
	DICE_ROOM="骰局$$"
	DICE_COMMON=(--headless --path "$ROOT" -- --bot --fast="$SPEED" --quit-after-match)
	run_capped "$GODOT" "${DICE_COMMON[@]}" --autohost=3 --mode=liars_dice --port="$DICE_PORT" --room="$DICE_ROOM" --name=骰房主 \
		>"$LOG_DIR/dice_host.log" 2>&1 &
	DHOST=$!
	sleep 2
	run_capped "$GODOT" "${DICE_COMMON[@]}" --discover="$DICE_ROOM" --name=骰发现 >"$LOG_DIR/dice_discover.log" 2>&1 &
	DDISCOVER=$!
	run_capped "$GODOT" "${DICE_COMMON[@]}" --autojoin="127.0.0.1:$DICE_PORT" --name=骰直连 >"$LOG_DIR/dice_direct.log" 2>&1 &
	DDIRECT=$!
	dice_winners=()
	for pair in "dice_host:$DHOST" "dice_discover:$DDISCOVER" "dice_direct:$DDIRECT"; do
		name="${pair%%:*}"
		pid="${pair##*:}"
		if wait "$pid"; then code=0; else code=$?; fi
		log="$LOG_DIR/$name.log"
		errors=$(grep -c "SCRIPT ERROR" "$log" || true)
		winner=$(grep -m1 -o "MATCH_OVER winner=[0-9]*" "$log" || true)
		dice_winners+=("$winner")
		if [ "$code" -ne 0 ] || [ -z "$winner" ] || [ "$errors" -ne 0 ] || ! grep -q "QUIPS heard=2" "$log"; then
			echo "FAIL $name (exit=$code, script_errors=$errors) — 日志:$log"
			grep -A3 "SCRIPT ERROR\|FAIL" "$log" | head -20
			status=1
		else
			echo "ok   $name — 吹牛骰子 $winner · $(grep -m1 -o "QUIPS heard=[0-9]*" "$log")"
		fi
	done
	if [ -z "${dice_winners[0]}" ] || [ "${dice_winners[0]}" != "${dice_winners[1]}" ] || [ "${dice_winners[0]}" != "${dice_winners[2]}" ]; then
		echo "FAIL liars_dice winner — 三端的胜者不一致:"
		printf '  %s\n' "${dice_winners[@]}"
		status=1
	else
		echo "ok   liars_dice — 三端胜者一致(${dice_winners[0]})"
	fi
fi
# —— 斗地主一局(正好 3 端)——
if [ "${SKIP_DOU_DIZHU:-0}" != "1" ]; then
	DDZ_PORT=$((PORT + 600))
	DDZ_ROOM="地主$$"
	DDZ_HANDS="${DDZ_HANDS:-3}"
	DDZ_COMMON=(--headless --path "$ROOT" -- --bot --fast="$SPEED" --quit-after-match)
	run_capped "$GODOT" "${DDZ_COMMON[@]}" --autohost=3 --mode=dou_dizhu --hands="$DDZ_HANDS" --port="$DDZ_PORT" --room="$DDZ_ROOM" \
		--name=地主房主 >"$LOG_DIR/ddz_host.log" 2>&1 &
	DHOST=$!
	sleep 2
	run_capped "$GODOT" "${DDZ_COMMON[@]}" --discover="$DDZ_ROOM" --name=地主发现 >"$LOG_DIR/ddz_discover.log" 2>&1 &
	DDISCOVER=$!
	run_capped "$GODOT" "${DDZ_COMMON[@]}" --autojoin="127.0.0.1:$DDZ_PORT" --name=地主直连 >"$LOG_DIR/ddz_direct.log" 2>&1 &
	DDIRECT=$!
	ddz_results=()
	for pair in "ddz_host:$DHOST" "ddz_discover:$DDISCOVER" "ddz_direct:$DDIRECT"; do
		name="${pair%%:*}"
		pid="${pair##*:}"
		if wait "$pid"; then code=0; else code=$?; fi
		log="$LOG_DIR/$name.log"
		errors=$(grep -c "SCRIPT ERROR\|^ERROR:" "$log" || true)
		result=$(grep -m1 "DDZ_RESULTS" "$log" | sed 's/.*DDZ_RESULTS //' || true)
		ddz_results+=("$result")
		problems=""
		[ "$code" -ne 0 ] && problems="$problems exit=$code"
		[ "$errors" -ne 0 ] && problems="$problems script_errors=$errors"
		grep -q "SESSION_OVER" "$log" || problems="$problems no_session_over"
		grep -q "QUIPS heard=2" "$log" || problems="$problems quips"
		[ -z "$result" ] && problems="$problems no_results"
		echo "$result" | grep -q "sum=0$" || problems="$problems sum"
		if [ "$name" = "ddz_host" ]; then
			hands=$(grep -c "DDZ_HAND_OVER" "$log" || true)
			[ "$hands" -ne "$DDZ_HANDS" ] && problems="$problems hands=$hands"
		fi
		if [ -n "$problems" ]; then
			echo "FAIL $name ($problems) — 日志:$log"
			grep -A3 "SCRIPT ERROR\|FAIL" "$log" | head -20
			status=1
		else
			echo "ok   $name — 斗地主 $result · $(grep -m1 -o "QUIPS heard=[0-9]*" "$log")"
		fi
	done
	if [ -z "${ddz_results[0]}" ] || [ "${ddz_results[0]}" != "${ddz_results[1]}" ] || [ "${ddz_results[0]}" != "${ddz_results[2]}" ]; then
		echo "FAIL dou_dizhu results — 三端的结算不一致:"
		printf '  %s\n' "${ddz_results[@]}"
		status=1
	else
		echo "ok   dou_dizhu — 三端结算一致、总和为 0(${ddz_results[0]},打了 $DDZ_HANDS 手)"
	fi
fi
[ "$status" -eq 0 ] && echo "联机冒烟通过(日志:$LOG_DIR)"
exit "$status"
