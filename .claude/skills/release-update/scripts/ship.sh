#!/usr/bin/env bash
# 发布一个已提交、已推送的版本:在该提交的干净 worktree 里跑测试、导出、签名,推更新源,建 GitHub Release。
# 工作区里别的会话没提交的改动永远不会进包;发布记录(last_build 等)始终写回主仓库的 build/。
#
# 用法:ship.sh test                            只在干净 worktree 里跑全量单测(推送前用)
#       ship.sh check                           只做发布前检查(不改任何东西)
#       ship.sh build "更新说明"                 检查 + 测试 + 导出两个平台安装包 + 签好更新包(还没对外)
#       ship.sh publish                          把 build 好的更新包推到 updates 分支,并等线上读到新 build
#       ship.sh github [发布说明.md]             用 tools/publish_release.sh 建 GitHub Release(tag v<version>)
#       ship.sh all "更新说明" [发布说明.md]     build + publish + github
# 环境变量:REF(默认当前目录的 HEAD)、GODOT、SHIP_OUT(试跑 build 的输出目录)、
#       SHIP_SKIP_TESTS=1(build 时不跑单测:CI 用,测试由推送前的 ship.sh test 负责)
set -euo pipefail

GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
ROOT="$(git -C "$(dirname "$0")" rev-parse --path-format=absolute --git-common-dir | sed 's#/\.git$##')"
OUT="${SHIP_OUT:-$ROOT/build}"   # SHIP_OUT 只用于试跑 build(产物与发布记录写到别处,不碰真的 build/)
KEY="${LIARS_UPDATE_KEY:-$HOME/.config/liarstavern/update_signing_key.pem}"
REMOTE="origin"
MAX_NOTES_CHARS=60       # 更新说明显示在主菜单提示条的一行里
FEED_WAIT_TRIES=14       # raw.githubusercontent.com 缓存最多 5 分钟:每 30 秒查一次,最多 7 分钟
FEED_WAIT_SECONDS=30
REF_SHA="$(git rev-parse --verify --quiet "${REF:-HEAD}^{commit}" 2>/dev/null \
	|| git -C "$ROOT" rev-parse --verify "${REF:-HEAD}^{commit}")"
WT=""

die() { echo "✗ $*" >&2; exit 1; }
ok() { echo "✓ $*"; }

json_field() {  # json_field <字段> <json 文件或 ->
	python3 -c 'import json,sys; v=json.load(open(sys.argv[2]) if sys.argv[2]!="-" else sys.stdin).get(sys.argv[1],""); print(v)' "$1" "$2"
}

at_ref() { git -C "$ROOT" show "$REF_SHA:$1"; }

worktree() {  # 该提交的干净 worktree,整个脚本只建一次,退出时删掉
	[ -z "$WT" ] || return 0
	WT="$(mktemp -d "${TMPDIR:-/tmp}/liars_ship.XXXXXX")"
	trap 'git -C "$ROOT" worktree remove --force "$WT" >/dev/null 2>&1 || true; rm -rf "$WT"' EXIT
	git -C "$ROOT" worktree add -q --detach "$WT" "$REF_SHA"
}

BUILD="$(at_ref build.json | json_field build -)"
VERSION="$(at_ref build.json | json_field version -)"
BASE="$(at_ref build.json | json_field base_build -)"
FEED_URL="$(at_ref src/update/build_info.gd | sed -n 's/^const FEED_URL := "\(.*\)"/\1/p')"
LAST_MANIFEST="$OUT/update/macos/manifest.json"

run_tests() {
	worktree
	echo "导入资源(干净 worktree 要先导入,否则 class_name 找不到)…"
	"$GODOT" --headless --path "$WT" --import >/dev/null 2>&1 || true
	echo "在 ${REF_SHA:0:7} 的干净 worktree 里跑单元测试…"
	local log want ran
	log="$(mktemp "${TMPDIR:-/tmp}/liars_ship_gut.XXXXXX")"
	# --fixed-fps 60:每帧按 1/60 秒推进、不等真实时间,wait_seconds 几乎不花时间(全量 6 分多钟 → 20 秒左右)
	if ! "$GODOT" --headless --fixed-fps 60 --path "$WT" -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit >"$log" 2>&1; then
		grep -E "\[Failed\]|FAILED|SCRIPT ERROR|Parse Error" "$log" | head -40
		die "单元测试没过(完整日志 $log),不发布"
	fi
	# 测试脚本解析失败时 GUT 只跳过它、照样报全部通过,所以还要核对跑了的脚本数
	want="$(find "$WT/tests" -maxdepth 1 -name 'test_*.gd' | wc -l | tr -d ' ')"
	ran="$(sed -n 's/^Scripts *\([0-9][0-9]*\).*/\1/p' "$log" | tail -1)"
	if [ "$ran" != "$want" ]; then
		grep -E "SCRIPT ERROR|Parse Error|Ignoring script" "$log" | head -20
		die "只跑了 ${ran:-0}/$want 个测试脚本(有脚本没加载起来,完整日志 $log),不发布"
	fi
	ok "单元测试通过($ran 个脚本,$(sed -n 's/^Passing Tests *\([0-9]*\).*/\1/p' "$log" | tail -1) 个用例)"
}

check() {
	echo "发布提交 $(git -C "$ROOT" log -1 --format='%h %s' "$REF_SHA")"
	echo "build.json:build $BUILD,version $VERSION,base_build $BASE"
	[ -f "$KEY" ] || die "缺少签名私钥 $KEY。不要重新生成:新私钥签的包所有已安装的游戏都不认,只能全员重装。找用户要备份"
	ok "签名私钥在"
	[ -x "$GODOT" ] || die "找不到 Godot:$GODOT"
	local engine; engine="$("$GODOT" --version | cut -d. -f1-4)"
	[ -d "$HOME/Library/Application Support/Godot/export_templates/$engine" ] || die "缺少 $engine 的导出模板"
	ok "Godot $engine 与导出模板"

	local last=0 last_version="" last_engine=""
	[ -f "$OUT/update/last_build" ] && last="$(cat "$OUT/update/last_build")"
	if [ -f "$LAST_MANIFEST" ]; then
		last_version="$(json_field version "$LAST_MANIFEST")"
		last_engine="$(json_field engine "$LAST_MANIFEST")"
	fi
	[ "$BUILD" -gt "$last" ] || die "提交里 build.json 的 build($BUILD)不比上次发布($last)大:改 build.json 并提交"
	[ "$VERSION" != "$last_version" ] || die "version 还是上次的 $last_version:改 build.json 的 version 并提交"
	ok "build $last → $BUILD,version ${last_version:-无} → $VERSION"

	local settings_sha; settings_sha="$(at_ref project.godot | shasum -a 256 | cut -d' ' -f1)"
	if [ -f "$OUT/update/project.godot.sha256" ] && [ "$(cat "$OUT/update/project.godot.sha256")" != "$settings_sha" ] \
			&& [ "$BASE" != "$BUILD" ]; then
		die "project.godot 自上次发布后改过,旧安装包叠加不了:把 build.json 的 base_build 设成 $BUILD 并提交"
	fi
	if [ -n "$last_engine" ] && [ "$last_engine" != "$engine" ] && [ "$BASE" != "$BUILD" ]; then
		die "引擎从 $last_engine 换成了 $engine,旧安装包叠加不了:把 build.json 的 base_build 设成 $BUILD 并提交"
	fi
	[ "$BASE" != "$BUILD" ] || echo "! base_build = build:老玩家都得重装,这一版只能靠新安装包获得"
	ok "base_build $BASE"

	git -C "$ROOT" fetch -q "$REMOTE"
	git -C "$ROOT" merge-base --is-ancestor "$REF_SHA" "$REMOTE/main" \
		|| die "提交 ${REF_SHA:0:7} 还不在 $REMOTE/main 上:先推送,玩家拿到的内容要和公开源码一致"
	ok "已推送到 $REMOTE/main"
	if git -C "$ROOT" ls-remote --exit-code --tags "$REMOTE" "v$VERSION" >/dev/null 2>&1; then
		die "远端已经有 tag v$VERSION:换一个 version"
	fi
	if gh auth status >/dev/null 2>&1; then ok "gh 已登录"; else echo "! gh 没登录:github 这一步做不了(让用户运行 gh auth login)"; fi
}

build() {
	local notes="$1"
	[ -n "$notes" ] || die "缺少更新说明(玩家在更新提示条上看到,一句话)"
	local chars  # 按字符数算(bash 的 ${#} 在非 UTF-8 环境下数的是字节)
	chars="$(python3 -c 'import sys; print(len(sys.argv[1]))' "$notes")"
	[ "$chars" -le "$MAX_NOTES_CHARS" ] || die "更新说明 $chars 字,太长:提示条一行放得下的一句话(≤$MAX_NOTES_CHARS 字)"
	check
	if [ "${SHIP_SKIP_TESTS:-0}" = 1 ]; then
		echo "! SHIP_SKIP_TESTS=1:跳过单测(推送前要在本机跑过 ship.sh test)"
		worktree
	else
		run_tests
	fi
	[ -z "$(git -C "$WT" status --porcelain --untracked-files=no)" ] \
		|| die "导入或测试改动了受版本管理的文件,导出会和提交对不上:$(git -C "$WT" status --porcelain --untracked-files=no | head -5)"
	echo "导出并签名…"
	OUT="$OUT" GODOT="$GODOT" bash "$WT/tools/release.sh" "$notes"
	[ "$(cat "$OUT/update/last_build")" = "$BUILD" ] || die "release.sh 没写下 build $BUILD"
	ok "build $BUILD(v$VERSION)导出完成,还没对外发布"
}

no_dry_run() { [ -z "${SHIP_OUT:-}" ] || die "SHIP_OUT 只用于试跑 build,不能拿试跑产物对外发布"; }

built_from_ref() {  # build/ 里的产物必须正是这个提交导出的
	[ -f "$OUT/update/last_build" ] && [ "$(cat "$OUT/update/last_build")" = "$BUILD" ] \
		|| die "build/ 里不是 build $BUILD 的产物:先 ship.sh build"
	[ -f "$OUT/update/last_commit" ] || die "build/update/last_commit 不存在,不知道产物是从哪个提交导出的:先 ship.sh build"
	local stamp; stamp="$(cat "$OUT/update/last_commit")"
	[ "$stamp" = "$REF_SHA" ] \
		|| die "build/ 里的产物是从 $stamp 导出的,不是 $REF_SHA(要发那一版就用 REF=$stamp 重跑)"
}

publish() {
	no_dry_run
	built_from_ref
	local plat
	for plat in macos windows; do
		[ "$(json_field build "$OUT/update/$plat/manifest.json")" = "$BUILD" ] || die "$plat 清单不是 build $BUILD"
	done
	worktree
	OUT="$OUT" bash "$WT/tools/publish_update.sh"
	echo "等线上更新源读到 build $BUILD(CDN 缓存最多 5 分钟)…"
	local tries manifest pck size
	manifest="$(mktemp "${TMPDIR:-/tmp}/liars_ship_feed.XXXXXX")"
	for plat in macos windows; do
		tries=0
		until curl -fsS -m 20 -o "$manifest" "${FEED_URL}$plat/manifest.json?t=$(date +%s)" 2>/dev/null \
				&& [ "$(json_field build "$manifest")" = "$BUILD" ]; do
			tries=$((tries + 1))
			[ "$tries" -lt "$FEED_WAIT_TRIES" ] || die "$plat:等了 $((FEED_WAIT_TRIES * FEED_WAIT_SECONDS)) 秒线上还不是 build $BUILD"
			sleep "$FEED_WAIT_SECONDS"
		done
		pck="$(json_field pck_file "$manifest")"
		size="$(curl -fsSI -m 20 "${FEED_URL}$plat/$pck" | tr -d '\r' | sed -n 's/^[Cc]ontent-[Ll]ength: *//p' | tail -1)"
		[ "$size" = "$(json_field pck_size "$manifest")" ] || die "$plat:线上 $pck 大小($size)和清单对不上"
		ok "线上 $plat:build $BUILD,$pck $size 字节"
	done
	rm -f "$manifest"
}

github() {
	no_dry_run
	built_from_ref
	local notes_file="${1:-}"
	if [ -n "$notes_file" ]; then
		[ -f "$notes_file" ] || die "找不到发布说明 $notes_file"
		notes_file="$(cd "$(dirname "$notes_file")" && pwd)/$(basename "$notes_file")"
	fi
	worktree
	[ -f "$WT/tools/publish_release.sh" ] \
		|| die "提交 ${REF_SHA:0:7} 里没有 tools/publish_release.sh:按 README「发布新版本」第 4 步手动传安装包"
	OUT="$OUT" TARGET="$REF_SHA" bash "$WT/tools/publish_release.sh" ${notes_file:+"$notes_file"}
}

case "${1:-}" in
	test) run_tests ;;
	check) check ;;
	build) build "${2:-}" ;;
	publish) publish ;;
	github) github "${2:-}" ;;
	all) build "${2:-}"; publish; github "${3:-}" ;;
	*) sed -n '2,11p' "$0"; exit 2 ;;
esac
