# ZCode 自托管 web 补丁

让 [ZCode](https://github.com/zai-org/ZCode)（v3.14.3，commit `29628c9`）的自托管
web 部署在手机浏览器上真正可用的一组源码改动。

**全部功能打在同一个文件里**：`zcode-selfhosted-web.patch`。
一次 `git apply` 装完，装完的代码与维护者分支逐字节一致。

## 一键安装

```bash
# 在 zai-org/ZCode 的源码目录里（需 checkout 到 v3.14.3，即 commit 29628c9）
git checkout 29628c9
bash /path/to/install.sh          # 本目录中的 install.sh

# 构建发行包
pnpm install
pnpm build:zcode
# 产物：dist/zcode/releases/<version>/zcode-<version>.tar.gz
# 解压到部署目录，重启服务即可
```

安装脚本自带三道保险：

1. 基线核对——当前代码不是 `29628c9` 就拒绝安装（可 `STRICT=0` 强行跳过，自担风险）；
2. 工作区干净核对——有未提交改动就拒绝安装；
3. 预检——先在临时索引上试装一遍，任何失败都原样退出，绝不留半装状态。

回滚：补丁改动在提交前随时可 `git checkout -- .` 全部丢弃；提交后可用
`git revert`。

运行服务（token 模式，页面首次访问可用 `?token=<token>`；开启配对登录后见功能 l）：

```bash
node bin/zcode.mjs --web --workspace <dir> --host 127.0.0.1 --port 3030 --token <token>
```

`--workspace` 指向应用管理的会话工作区（`<dataBaseDir>/.zcode/workspace/default`）
时会被标注为 `workspacePurpose: "conversation"`——界面显示为"未在项目中工作"。
真实项目在界面上按需新建。

## 功能清单

源码级、协议兼容的增量改动，不影响桌面端，不含任何环境特定的值。

| # | 功能 | 解决什么问题 |
|---|------|--------------|
| a | 远控页 `@` 菜单 | 官方远控页调用的是 3.14.3 之前的旧一次性文件列表接口，服务端只实现了新的分块接口 → 菜单报 `Method not found`。补一个兼容旧形状的接口，复用服务端工作区文件索引缓存 |
| b | 直连页侧栏任务列表 | 侧栏"任务"区走的是桌面 Host 才有的 RPC 通道 → 永远超时空列表。在服务端补一个转发给内置任务服务的最小通道（与桌面同源 tasks-index.sqlite） |
| c | token 模式 server-info | web 入口取 `/api/server-info` 不带凭据 → 服务端带 `--token` 时永远 401，工作区信息到不了页面。让该请求带上 URL 里的 `?token=`（与 WebSocket 同一凭据） |
| d | 会话恢复 | web 入口从未开启会话恢复 → 启动时没有任何工作区标签页。开启与桌面端相同的恢复路径 |
| e | 工作区用途标注 | server-info 的工作区信息没有用途字段 → 无法区分会话工作区和真实项目。加一个向后兼容的 `workspacePurpose` 字段 |
| f | 手机后台断连守卫 | 手机浏览器切后台几秒就冻结/杀掉 WebSocket；回前台时连接已死且无提示，RPC 静默失败。真实 `close` 事件才判死；判死即进入恢复（见 j） |
| g | 手机抽屉布局 | <768px 时侧栏和右侧面板把会话区挤成窄条。改成滑出式浮层（宽 min(85vw,480px)、200ms 动画、点遮罩关闭、互斥、左上角开关总在最上层） |
| h | 目录浏览器新建文件夹 | 服务端目录浏览器原本只能选已有目录，手机上没法建项目目录。服务端新增单段 `createDirectory` 接口 + 目录浏览器内联"新建文件夹"表单，中英文文案齐备 |
| i | 手机顶栏与触屏细节 | (1) 顶栏在侧栏收起时保留桌面窗控占位 → 手机上标题被挤出屏；(2) 消息操作栏（时间/复制）纯悬停触发 → 触屏上永远看不见；(3) 切后台回来被误判断连 → 每次快速切换都整页重载；(4) 问答框回答显示"未提供回答"（CLI 输出文本形态，解析器只认 JSON）。以上全部修复 |
| j | 断线原地恢复 + 滚动记忆 | 断线原本整页重载：白屏、7MB 重新下载、丢失阅读位置。改为软重连——页面不重载，顶部横幅提示，恢复语义不变。滚动位置镜像到 `sessionStorage`（LRU 40），按"距底部距离"恢复，带 4 秒收敛；用户主动滚动立即取消恢复。另修复一个每次页面加载都会触发的潜在渲染崩溃（`useProviderSettingsView` 向 `getServerSnapshot` 重复传参，React 19 下抛 `TypeError`） |
| k | WebSocket 存活检测 | 浏览器↔服务端 WebSocket 原本零存活探测：半开连接看起来一切正常，所有新请求却静默失败。两端心跳（15s 探测 / 30s 无帧判死）+ 服务端 RFC 6455 ping 循环，判死即触发 j 的原地恢复 |
| l | 配对登录（可选，`ZCODE_PAIRING=1`） | URL 带 token 的直连方式会留在浏览器历史/日志里。开启后：管理员用 token 生成一次性配对码（12 字符、10 分钟有效、单次使用、服务端只存摘要），手机上输入配对码换 90 天 HttpOnly Secure cookie；此后 URL 直连在 `/api/*` 与 `/ws` 一律 401——配对登录才有意义。页面导航未登录时自动跳到配对页。默认关闭，不开时行为与官方版本逐字节一致 |

规格与测试：keepalive 协议层 `packages/rpc/specs/socket-keepalive.md` +
`packages/rpc/test/socket-keepalive.test.ts`；自托管 web 的验收场景
`packages/server/specs/selfhosted-web-pairing.md`。

### 第 k/j 项的恢复架构（实机迭代后的现状）

1. **热换底**——重连时新 WebSocket 原地换进同一个 `ChannelClient`：挂起请求
   fail-closed、缓冲帧（含服务端 `Initialize`）重放、事件订阅重发、握手缓存按
   纪元失效。React 树不重挂，页面零视觉变化。
2. **有界静默重试**——订阅失败按 250ms→8s 退避（对齐 8s 握手超时，约 75s 预算），
   瞬态抖动对用户不可见。
3. **服务端连接卫生**——RFC 6455 ping 循环（宽松容忍 ≈2.5 分钟，照顾手机后台省电），
   超时主动断开，触发浏览器侧 `close` 恢复路径。
4. **Service Worker 缓存（v9）**——页面导航改为网络优先（只有 ok 响应进缓存，离线
   才回退缓存），杜绝旧缓存 shell 拿过期凭据反复失败导致"启动失败"假象；其余静态
   资源 immutable 缓存。注入脚本（状态栏 boot、探针）网络优先，修复永远能到达客户端。
5. **稳定标签页标题**——打包产物会在运行时改标题；注入探针把它固定为 `Zcode`。
6. **配对登录细节**——cookie 即主 token（单 token 架构）；换 token 即全员重新配对；
   提交接口按 IP 限速 10 次/10 分钟；配对页不做重定向（有旧 cookie 的浏览器也总能
   看到表单）；设备按 (IP, UA) 指纹记录用于观察。

### 已知边界

- `document.wasDiscarded` 整页丢弃（Android 内存管理）仍会产生一次页面加载——本地
  缓存秒开（约 1 秒），web 代码无法阻止。
- 官方远控页 `/remote/v4` 是闭源页：无原生恢复协调器，靠注入 shim（横幅 + 不可恢复
  时才重载）；且需要下面的 relay 才能用。
- 服务端被杀时任务行可能停留在 `running`（启动时无孤儿清理）。

## 仓库结构（三件套）

| 文件 | 作用 |
|------|------|
| `zcode-selfhosted-web.patch` | **唯一补丁**：全部功能，单文件，一次 `git apply` |
| `install.sh` | 一键安装脚本（基线核对 → 预检 → 应用，任一失败不留半装状态） |
| `README.md` | 本文档 |

可选附加（部署工具，不是源码补丁）：

- [`relay/`](relay/) — 官方手机远控页的自托管中转服务（端点、环境变量、
  systemd/nginx 接线见其 README）。
- [`e2e/`](e2e/) — 半开黑洞、原地恢复、重载遥测等实机验证脚本。

## 自托管清单（补丁之外）

- **插件包**：官方发行版自带的插件包（`skill-creator-plugin`、`zcode-guide-plugin`、
  `documents-plugin`、`spreadsheets-plugin`、`pdf-plugin`、`presentations-plugin`、
  `restore-legacy-sessions-plugin`、`browser-use-plugin`、`bundled-skills` 等）**不在
  源码树里**，`pnpm build:zcode` 不产出。`<install>/packages/` 需自行从官方发行物复制，
  否则插件商店与技能/指南工具缺失。
- **插件与 agent 产物同版**：插件定义声明了 `requiredSeedPaths`（如 `zcode-guide`
  需要 `commands/workflow.md` 与 `skills/dynamic-workflows/*`）；启动时逐路径核对，
  缺失则记 `ZCODE_PLUGIN_SEED_INCOMPLETE` 并**跳过该插件播种**。源码构建与插件副本
  必须来自同一发行版。
- **agent 运行时包**：`<install>/agent/zcode.cjs` 是预构建产物；从源码重建会覆盖它，
  每次 agent 包更新后都要重新核对上一条。

## 维护者纪律

- **应用原子性**：`install.sh` 在临时索引上累积试装，失败即原样退出；基线不符是硬
  错误（`STRICT=0` 自担风险）。回滚 `git checkout -- .` 或 `git apply -R`。
- **每次补丁更新必须重验整链**：干净 `29628c9` 工作树 + 本补丁 → 树哈希必须等于
  维护者 HEAD 的树哈希。当前目标值：`33600321a9abf7a4e03203ffb694cbce64fae068`。
- **已知验证缺口**：协议层有单元测试（心跳回显、事件重发）；端到端恢复靠上述 e2e
  脚本在真机上验证，尚无自动化的干净基线构建 + 离线恢复 CI。这是最有价值的下一步。
