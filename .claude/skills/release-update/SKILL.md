---
name: release-update
description: Use when the user asks to 打包、发布、发版、出新版本、推送在线更新、让玩家更新到最新、上传安装包到 GitHub Releases, or to ship / release / publish a new build of 骗子酒馆 (Liar's Tavern); also when build.json, tools/release.sh, tools/publish_update.sh, tools/publish_release.sh, tools/ci_release.sh, .github/workflows/release.yml (the Release CI), the updates branch or the signing key come up in a release context; also when watching or fixing a Release CI run.
---

# 发布更新(骗子酒馆)

## 原则

**发布 = 把改好 `build.json` 的提交推到 origin/main。** main 上 `build.json` 的 `version` 一变(远端还没有 tag `v<version>`),GitHub Actions(`.github/workflows/release.yml`)就自动发布：导出签名、推 `updates` 分支、建 GitHub Release，全部复用 `scripts/ship.sh`,和本机发布是同一套检查。**CI 不跑单测**(在 GitHub 的 macOS 机器上要跑半小时以上),所以推送前必须在本机跑过 `$SHIP test`。本机 `$SHIP` 只在 CI 用不了时兜底，两边绝不同时发同一版。

用户说「发布」就等于授权推更新源和建 GitHub Release，不用再确认，也不要问版本号这类问题，自己定、事后汇报。用户没让发布时，绝不自己发：更新推出去后，所有玩家下次启动就会装上，**撤不回**。推 main 那一下可能被自动模式的权限拦下(视为上线操作):先把提交做好，告诉用户要推的命令，等用户放行，不要绕路推。

主工作区常有别的会话没提交的改动，别的会话也会随时往 main 推提交。**发布提交在基于 origin/main 的独立 worktree 里做**，不在共用的主工作区里切分支、改 `build.json`。

## CI 怎么跑

`plan`(ubuntu,几秒)→ `build`(macOS:装 Godot 与导出模板、核对签名私钥、按线上更新源补上一版记录、`SHIP_SKIP_TESTS=1 ship.sh build`,不跑单测)→ `publish`(ubuntu:`ship.sh publish` 推更新源并等线上生效、`ship.sh github` 建 Release)。

- 签名私钥在仓库 secret `LIARS_UPDATE_SIGNING_KEY`,CI 会核对它和 `src/update/update_key.gd` 的公钥是一对。
- Godot 版本写在 release.yml 的 `GODOT_VERSION`;升级引擎时一起改，并把 `base_build` 设成新 build。
- 辅助脚本 `tools/ci_release.sh`:`plan`(发不发、更新说明)、`key`、`seed`(没有本机 `build/` 记录时从线上补)、`published`(重跑时认出已推过的更新源)。
- 也可以在 Actions 页面手动运行 Release(`gh workflow run release.yml -f notes="新增:……"`),用来补发 main 上已改好 version、但还没发的版本。

## 流程

`SHIP=.claude/skills/release-update/scripts/ship.sh`(不带参数运行会打印用法)

1. **看要发什么**：`git fetch -q --tags origin && git log --oneline $(git describe --tags --abbrev=0 origin/main)..origin/main`,加上自己还没推的改动。没有新内容就不发。
2. **在 worktree 里准备发布提交**:`git worktree add -q --detach .claude/worktrees/release origin/main`(已存在就 `git -C <它> checkout -q --detach origin/main`)。自己的功能改动先按平常方式提交推送；只 `git add <具体文件>`,不用 `git add -A`、`git add .`。
3. **改 `build.json`**:
   - `build` 加一，每次发布都要加，哪怕只是重发。
   - `version`：修 bug 改第三位，新玩法或新功能改第二位。
   - `base_build`：改了 `project.godot`(自动加载、渲染设置等)、升级了 Godot，或者新内容依赖 `src/update/update_boot.gd` / `update_key.gd` 的改动(这两个文件只随安装包生效)时，设成新的 `build`；否则不动。设了就意味着**所有老玩家都得重装**，要在汇报和 Release 说明里写清楚。判断方法：`git diff --stat v<上一版> origin/main -- project.godot src/update/update_boot.gd src/update/update_key.gd`。
   - `notes`:给玩家看的更新说明，显示在主菜单提示条的一行里：一句话，不超过 60 字，以「修复:」或「新增:」开头。和线上上一版一样时 CI 会拦下。
   - GitHub Release 正文可选写在 `docs/releases/v<version>.md`,不写按模板生成。`base_build = build` 时一定要写，第一段就说明老玩家需要重新下载安装包(没有这个文件 CI 不发)。
   - 提交信息照惯例把版本写在末尾：`chore: 发布 0.9.1:……;版本 0.9.1`。
   - 写完先自检:`GITHUB_OUTPUT=/dev/null bash tools/ci_release.sh plan`,要输出「发布 v…」。
4. **推送前必须先测**:`$SHIP test`(在 worktree 里运行，半分钟左右)。CI 不跑单测，这是发出去之前唯一一道测试。没过就不推送，先修(superpowers:systematic-debugging)。rebase 进了别人的提交后要重测。
5. **推送 = 发布**：推之前再 `git fetch -q origin`;main 动过就 `git rebase -q origin/main`,并用 `git log --oneline <上次看过的 main>..origin/main` 看清多出来的提交——它们会一起进这一版，要在汇报里说。确认 `build.json`、`project.godot` 没被别人改，然后 `git push origin HEAD:main`。推不上(非快进)就重复这一步，绝不强推。push 时提示「Changes must be made through a pull request」是正常的(账号可绕过规则)。
6. **盯 CI**:`gh run list -R Murphycx94/liars-tavern --workflow release.yml -L 3` 找到这次运行(headSha 是刚推的提交),把链接给用户，然后后台运行 `gh run watch <id> -R Murphycx94/liars-tavern --exit-status --interval 30`。失败时 `gh run view <id> --log-failed` 看原因，publish 步骤的偶发失败(网络、CDN 缓存)直接 `gh run rerun <id> --failed`(会认出已推过的更新源，只补 Release);build 步骤失败见下表。更新源已经推出去后又要改内容，只能 build 加一、改 version 重发。
7. **汇报并更新记忆**：汇报版本、build、更新说明、Release 链接(`gh release view v<version>`)、一起发出去的别人的提交，以及是否需要重装；然后更新记忆 `liars-tavern-release-flow` 里「已经发布到哪个 build」那一条。

## 本机兜底(只在 CI 用不了时)

先确认 CI 没在发这一版(`gh run list --workflow release.yml`),必要时在 Actions 页面停用 Release 工作流。然后在发布提交的 worktree 里：`$SHIP all "修复:……" [发布说明.md]`,放到后台执行。

- 第一个参数就是 `notes` 那句更新说明；发布说明.md 是 Release 正文，可以不给。
- `all` 依次做：检查，测试，导出并签名，推 `updates` 分支并等线上读到新 build，建 GitHub Release `v<version>`(发布后会下载回来核对)。任何一步失败，后面的都不做。要分步执行时，用 `check`、`build`、`publish`、`github` 这几个子命令。
- 需要本机的签名私钥 `~/.config/liarstavern/update_signing_key.pem`、Godot 与导出模板、`gh auth login`。

## 出了问题

| 情况 | 处理 |
|---|---|
| CI 的 build 步骤失败(导出失败、check 不通过) | `gh run view <id> --log-failed`;按下面对应的行修好，提交推送。还没推更新源，所以不用加 build。没改 `build.json` 的推送不会触发，修好后 `gh workflow run release.yml -R Murphycx94/liars-tavern` 在最新 main 上重跑(`rerun` 用的还是旧提交) |
| `check` 报 build 没加、version 没改、base_build 不对、没推送、tag 已存在 | 按提示改 `build.json` 或推送，提交后重跑 |
| 测试没过，或者「只跑了 N/M 个测试脚本」 | 不发布。后一种是某个测试脚本解析失败被 GUT 悄悄跳过了，照样要修 |
| 缺签名私钥 `~/.config/liarstavern/update_signing_key.pem` | **停下，找用户要备份。绝不运行 `tools/make_update_key.gd` 重新生成**：新私钥签的包，所有已安装的游戏都不认 |
| `publish` 等不到线上的新 build | raw.githubusercontent.com 的缓存最多 5 分钟；重跑 `$SHIP publish`(可以重复执行) |
| `github` 失败(gh 没登录、网络问题、提交里没有 `tools/publish_release.sh`) | 更新源已经生效了。修好后单独重跑 `$SHIP github`；gh 没登录就让用户运行 `gh auth login` |
| CI 报 `LIARS_UPDATE_SIGNING_KEY` 没配或和公钥不是一对 | 让用户在仓库 Settings → Secrets and variables → Actions 配好(内容是本机 `.pem` 全文:`gh secret set LIARS_UPDATE_SIGNING_KEY < ~/.config/liarstavern/update_signing_key.pem`),然后 rerun |
| CI 的 plan 报缺更新说明、说明和上一版一样 | 改 `build.json` 的 `notes` 提交推送(会再次触发);或在 Actions 页面手动运行 Release 并填 notes |
| 发出去的版本有严重问题 | **没法回退**：游戏只接受更大的 build。立刻修好，build 再加一重新发。在那之前，玩家可以加启动参数 `-- --no-update` 退回安装包自带的版本；更新后的版本连续两次启动失败，游戏也会自动退回 |

## 红线

- 在共用的主工作区里直接跑 `tools/release.sh`(会把别人没提交的改动打进包；`OUT` 不对时还会绕过 build 号检查)
- 发布没提交或没推送的代码、同一个 build 号发两次
- 在共用的主工作区里切分支、rebase 或改 `build.json` 做发布提交；用户没明确让发布时往 main 推版本号
- 手动改或强推 `updates` 分支、把 `.pem` 放进仓库
- 不打算发布时在 main 上改 `build.json` 的 `version`(一推上去 CI 就发了)
- CI 在发某一版时，本机再跑 `$SHIP publish` / `github` 发同一版
- 用 `SHIP_OUT` 试跑出来的产物对外发布(脚本也会拦)
