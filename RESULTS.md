# migo-bench 对比结果

> 中文为默认版本；英文见 [RESULTS.en.md](RESULTS.en.md)。
> 原始数据:`out/results.csv`(稳态)、`out/stress_*.csv`(压力曲线)。每行都带完整溯源(Migo 版本、设备、WebView 版本、时间戳、`fps_source`)。
> **本轮(2026-07 重跑)口径变更**:Migo 用 **release** 构建(opt-level "z" + LTO,实际出货配置);此前发布的数字是 debug(opt-level 0)构建,两者不可直接回归对比,故本页数字**取代**旧版。见 §6「与旧版差异」。

## 1. 结论先行

同一游戏、同一设备、同一交互,在 **Migo 原生运行时(release)** 与 **Android 系统 WebView** 上对比。定位:Migo = 开源原生的 WebView 替代。**头条是一致性 + 可审计 + 内存/CPU/启动效率;帧率近乎打平;并诚实报告一处重载回归。**

- ✅ **内存:Migo 明显更省,且三款游戏一致 ~40%**(bunnymark 138 vs 235、endless-runner 228 vs 391、canvasmark 137 vs 220 MB)——关键:WebView 的渲染跑在**独立的 chromium 进程**里,必须算进去才公平(否则少算 ~100MB)。
- ✅ **CPU:Migo 约为 WebView 的 40%(~2.4–2.7× 少),三款游戏一致**——原生 GL/Skia 比 Chromium 合成器更省 CPU;也是功耗的代理指标。
- ✅ **启动:Migo 更快**——游戏就绪(`Fully drawn`)三款都比 WebView 快(bunnymark 493 vs 536、endless-runner 658 vs 828、canvasmark 469 vs 523 ms)。
- = **帧率(常规负载):近乎打平**——Migo ~58fps vs WebView 60fps(Migo 1% low 略低),三款一致。
- 🎉 **canvasmark 内存泄漏已修复**——上一版的诚实反例(Canvas2D 每-fill 泄漏 GL 资源、内存锯齿 150–285MB)在本版**消失**:实测 42s 稳定在 ~104MB。见 §3.7。
- ⚠️ **诚实回归(重载吞吐)**——合成压力测试拉到 2 万精灵以上,**Migo 反而落后 WebView**(4 万处 29 vs 60fps、10 万处 20 vs 31fps)。这与上一版(debug)基线相反,是本轮可信重跑暴露的真实问题,最可能与 R2 命令流/逻辑-DB 渲染路径在超高精灵数下的每帧开销有关,**待 profile 归因与修复**。见 §3.3。

> 注意:这是**高端机**(麒麟 990)。常规负载多数指标 Migo 占优;GTM 楔子市场是**低端机**(内存小、易降频),内存/启动差距预计更大——低端机是下一步核心测试(见矩阵)。

## 2. 测试矩阵(设备 × 游戏)

| 设备档位 \ 游戏 | bunnymark (Pixi/WebGL) | endless-runner (Phaser/WebGL) | canvasmark (Canvas2D) |
|---|---|---|---|
| **高端** · 华为 Mate30 Pro(麒麟990/8G/A12) | ✅ 已测 | ✅ 已测 | ✅ 已测 |
| **中端**(~4G,待采购) | 🔜 | 🔜 | 🔜 |
| **低端** ⭐(~2-3G,待采购,GTM 楔子) | 🔜 | 🔜 | 🔜 |

> 1 台设备 × 3 游戏已跑通(覆盖两条渲染路径:WebGL × 2 + Canvas2D × 1)。
> **跨游戏结论(本轮修正)**:常规负载下 Migo 的领先幅度**三款游戏高度一致**(内存 ~40%、CPU ~2.4–2.7×),并非上一版所称"游戏越重差距越大"——那是旧 debug 基线里一次 CPU 采样失真(endless CPU 误录 18%)造成的假象。真实图景:Migo 在常规负载下有一层**稳定的低底噪优势**,与游戏轻重基本无关。
> **两条路径都覆盖**:WebGL(Pixi/Phaser)与 Canvas2D(Skia)Migo 都原生实现、60fps 渲染无碍——"WebView 替代"不止 WebGL。

## 3. 结果:Mate30 Pro × bunnymark(100 精灵,60s 稳态)

### 3.1 内存 🏆 Migo

| 指标 | WebView | Migo | 差异 |
|---|---|---|---|
| PSS 峰值 | **~235 MB** | **~138 MB** | **Migo 少 ~41%** |

- **公平口径**:WebView = 主进程 + chromium 沙箱渲染进程之和(`dumpsys meminfo <pkg>` 只算主进程,会漏掉渲染进程约 100MB)。Migo 是**单进程**,全部计入。
- PSS 有 ±几十 MB 抖动(GC/系统状态);多轮平均会更稳,方向(Migo 明显更省)稳健。

### 3.2 启动 🏆 Migo

**游戏就绪(系统 `Fully drawn`,游戏首个真实帧 → `reportFullyDrawn()`,公平口径):**

| 指标 | WebView | Migo | |
|---|---|---|---|
| 游戏就绪(凉机) | 536 ms | 493 ms | Migo 快 ~8% |

- 凉机下 Migo 已略快(V8 快照抵消原生初始化 + 无 Chromium 进程拉起)。热机/降频场景(低端机 + 长时间游玩)对 WebView 的 Chromium 冷启动更不利,历史观测过 WebView 慢 2× 以上(待凉机/热机分档复现,本轮只报凉机)。
- "首帧(`Displayed`)"对 WebView 是空白窗口先绘制、偏早,两侧口径不一;Migo 还多一层 Launcher→Game 跳转 → **以"游戏就绪"为准**。

### 3.3 帧率:常规打平;重载 ⚠️ Migo 落后(待修)

**常规负载(100 精灵):**

| 指标 | WebView | Migo |
|---|---|---|
| fps 中位 | 60 | 58 |
| 1% low | 60 | 56 |

**压力曲线(游戏内确定性 ramp 到 22 万精灵,`--scenario stress`)—— ⚠️ Migo 在 >2 万精灵后落后**:

| 精灵数 | WebView fps | Migo fps | |
|---:|---:|---:|:---|
| ≤20 000 | 60 | 55–58 | 打平 |
| **40 000** | **60** | **29** | WebView 领先 |
| **70 000** | 41 | 28 | WebView 领先 |
| **100 000** | 31 | 20 | WebView 领先 |
| 140 000 | 23 | 19 | WebView 领先 |
| 180 000 | 15 | 14 | 接近 |
| 220 000 | 12 | 11 | 接近 |

- ≤2 万精灵两侧都 55–60fps(高端机天花板)。**过了 2 万,WebView 的 Chromium WebGL 批处理明显更抗压**:4 万处 WebView 还 60、Migo 已掉到 29。knee(≥55fps):Migo ~2 万、WebView ~4 万。
- **⚠️ 这是相对上一版(debug 基线)的回归**——旧版称 Migo 重载领先 ~1.9×(10 万处 32 vs 17),本轮两次独立重跑一致显示相反(10 万处 Migo 20、WebView 31,采样 20/20/20/20/19 极稳,非噪声)。
- **最可能的元凶**:R2 类型化 GL 命令流对**大顶点缓冲的每帧序列化开销随精灵数线性增长**(10 万精灵每帧 ~MB 级顶点数据要过命令流),或 wx-way 逻辑-DB 上采样路径的额外每帧成本。**需 GPU profile 归因后修复**(不做无根据的猜测式改动)。
- 真实小游戏一般在数百~数千精灵区间(即"常规负载",Migo 稳态占优);2 万+ 是合成极限压测。但这条曲线是本框架该暴露的真实短板,不回避。

### 3.4 CPU 🏆 Migo

| 指标 | WebView | Migo | 差异 |
|---|---|---|---|
| CPU 占用(多核,可 >100%) | **~125%** | **~48%** | **Migo ~2.6× 少** |

- 口径:`/proc/<pid>/stat` 的 (utime+stime) 增量;WebView 计入主进程 + chromium 渲染进程(与内存同理)。
- 采样已改为**唤醒屏幕 + 多窗口取中位数**(见 §4)——上一版单窗口偶发把 Migo 误录成 6%(踩到 fps 采集后的空闲窗口),本轮修正。
- 同帧率下 Migo CPU 约为一半 → 更省电(见功耗)。

### 3.5 功耗(代理)

真机功耗直接测量在本机受限:该 EMUI 设备**关闭了 fuel gauge**(`current_now` 不可读)且 **per-uid batterystats 能量模型不可用**,加上 USB 供电会掩盖电池放电。**当前以 CPU 占用作为功耗代理**(定帧率下 CPU 是主要功耗驱动)→ Migo 更省。
真·功耗待:①非华为设备(开放 fuel gauge)②断电跑 + 电量差 ③外接功率计。

## 3.6 第二款游戏:endless-runner(Phaser)—— 领先幅度与 bunnymark 一致

第二款游戏用的是 **Phaser 3** 引擎的完整 webpack 打包产物(真实小游戏,不是合成基准),同设备、同口径、60s 稳态、横屏(两侧均按 game.json `landscape` 锁定,口径一致):

| 指标 | WebView | Migo | 差异 |
|---|---|---|---|
| **PSS 峰值** | **~391 MB** | **~228 MB** | **Migo 少 ~42%** |
| **CPU(多核)** | **~128%** | **~48%** | **Migo ~2.7× 少** |
| 游戏就绪(`Fully drawn`) | 828 ms | 658 ms | **Migo 快 ~21%** |
| fps 中位 / 1% low | 60 / 60 | 58 / 56 | 近乎打平 |
| fps 来源 | game-telemetry | game-telemetry | 两侧同源(EMUI 屏蔽 SurfaceFlinger) |

**跨游戏对比:**

| 指标 | bunnymark(Pixi) | endless-runner(Phaser) | canvasmark(Canvas2D) |
|---|---|---|---|
| 内存(Migo/WebView) | 138/235 → −41% | 228/391 → −42% | 137/220 → −38% |
| CPU | 48/125 → 2.6× | 48/128 → 2.7× | 74/175 → 2.4× |
| 游戏就绪 | 493/536 | 658/828 | 469/523 |
| fps | 58/60 | 58/60 | 58/60 |

**结论(修正)**:常规负载下,Migo 的领先幅度**三款游戏高度一致**(内存 ~40%、CPU ~2.4–2.7×、启动更快、fps 近平)。这来自 **Migo 原生运行时一层稳定的低底噪开销**;WebView 的 Chromium 税则始终更高。上一版所称"游戏越重差距从 33% 拉大到 61%、CPU 到 7×"**不成立**——那是旧 debug 基线里 endless-runner CPU 一次采样失真(误录 18%,与被修掉的 6% 同源)造成的假象;可信重跑后差距是一致的 ~40% / ~2.5×。

> 单轮采样(与 bunnymark 同口径),方向差距稳健;绝对值多轮平均会更稳。endless-runner 的 fps 遥测=引擎无关的 rAF 计数器(两侧注入完全相同代码 `[endless-runner] fps=N`),WebView 的"游戏就绪"由注入的 `AndroidBench.ready()` 首帧回调触发、Migo 由原生 onGameReady 触发 —— 新游戏接入本框架要满足的**遥测契约**。

## 3.7 第三款游戏:canvasmark(Canvas2D)—— 上一版的反例已修复 🎉

第三款游戏走**另一条渲染路径**:纯 Canvas 2D(不是 WebGL)。canvasmark 是 bunnymark 的 2D 版——每帧 `save/translate/rotate/fillRect` 画 N 个旋转方块,tap 加精灵,100 起步。**Migo 原生实现了 Canvas2D(Skia 支撑),`getContext('2d')` 是真的 2D 上下文,60fps 渲染没问题**。

| 指标 | WebView | Migo | 读法 |
|---|---|---|---|
| **PSS 内存** | **~220 MB(稳)** | **~137 MB(稳,实测 ~104MB 平)** | **Migo 少 ~38% ✅** |
| CPU(多核) | **175%** | **74%** | **Migo ~2.4× 少** ✅(Canvas2D 两侧都比 WebGL 吃 CPU,Migo 仍省一半多) |
| fps 中位 / 1% low | 60 / 60 | 58 / 57 | 近乎打平 ✅ |
| 游戏就绪 | 523 ms | 469 ms | **Migo 快 ~10%** ✅ |

**上一版的反例已修复 🎉**:旧 debug 版这里 Migo **内存反而更高更抖**——PSS 锯齿式在 ~150–285MB 之间涨-回收,根因(当时用本框架 bisect 定位)是 **Canvas2D 每次 fill 绘制泄漏 ~400 字节被锁定的 GL 资源**。**本轮 release 重跑,该泄漏消失**:migo canvasmark 内存实测 42s 稳定在 ~104MB(每 6s 采样:103/103/103/103/103/104/103 MB,无锯齿、无增长),PSS 峰值 137MB 也远低于 WebView 的 220MB。R2/R3/release 路径已把这个 per-draw GPU 资源泄漏解决。

> 这正是本框架的价值:上一版诚实报告了这个反例,本轮如实验证它被修复(README「Regression workflow」的意义)。fps 全程 ~58–60。fps 遥测=游戏自带 rAF 计数器 `[canvasmark] sprites=N fps=M`(两侧同源)。

## 4. 测量方法(系统级、app 无关、可审计)

- **内存**:`dumpsys meminfo`,WebView 求和主进程 + `:sandboxed_process`(`webview_pss.py`)。
- **启动**:系统 `am` 的 `Displayed`(首帧)+ `reportFullyDrawn`/`Fully drawn`(游戏就绪);不解析 app 日志。
- **帧率**:优先 `dumpsys SurfaceFlinger --latency`(合成器真实呈现时间戳,app 无关);**本设备 EMUI 屏蔽了该接口(全 0)**,回退到游戏自身 fps 遥测(两侧同源、对称),每行记 `fps_source`。非华为机会用 SurfaceFlinger。
- **CPU**:`/proc/<pid>/stat` (utime+stime) 增量(WebView 含渲染进程)。**取 3 个短窗口的中位数、且采样前唤醒屏幕保持**——单个 3s 窗口偶发会落在 fps 采集后的空闲/停顿瞬间读出荒谬低值(曾把 Migo 误录 ~6%),中位数排除该离群点。
- **压力**:游戏内确定性精灵 ramp(Pixi ticker,两侧一致;`make-stress-game.sh` 生成),fps 对精灵数作曲线。
- **朝向一致**:两个 shell 都按游戏 `game.json` 的 `deviceOrientation` 锁朝向(bunnymark/canvasmark 竖、endless-runner 横)——否则一横一竖渲染尺寸不同、不可比。
- **稳定性护栏**:采集前强制亮屏保持(`svc power stayon`)——熄屏会导致 activity 停止、零帧零数据。
- **启动时间解析**:ActivityManager 的 `Displayed/Fully drawn` 在 <1s 时是 `+868ms`、≥1s 时变成 `+1s43ms`——解析必须处理秒/分单位。
- **热节流提示**:麒麟 990 连续跑热会降频。同一轮里两侧**背靠背 + 游戏间 cooldown**测(本轮全程 29–35°C),相对对比公平;绝对值需凉机复现。

## 5. 复现

```bash
export PATH=$PATH:$ANDROID_HOME/platform-tools
# Migo 用 release AAR(出货配置):
#   scripts/build-aar.sh release arm64-v8a   （见 migo 仓库；bench 需可继承的公共 API，release 需临时关 library minify）
# 稳态:
bash scripts/run.sh --runtime webview --game bunnymark --device <SERIAL> --duration 60 --cold-runs 3
bash scripts/run.sh --runtime migo    --game bunnymark --device <SERIAL> --duration 60 --cold-runs 3 --migo-aar local:.../migo-release.aar
# 压力曲线:
bash scripts/run.sh --runtime migo    --game bunnymark --device <SERIAL> --scenario stress --duration 55 --migo-aar local:...
```

```bash
# 对比 / 回归门(Migo vs WebView 表 · 或新 Migo vs 基线):
python3 scripts/compare.py --results out/results.csv --game bunnymark --vs-webview
python3 scripts/compare.py --results out/results.csv --baseline baselines/mate30.csv --game bunnymark
```

Migo 版本可 pin:`--migo-aar local:PATH | release-tag:TAG | sha:SHA`——每个结果都钉在确切的 Migo 版本上(可审计)。基线快照在 `baselines/`(本轮已更新为 release);旧 debug 基线备份在 `baselines/mate30.debug-ff29aa4.bak.csv`。

## 6. 与旧版(debug / ff29aa4)差异

本轮换成 **release** 构建并修了两处测量 bug,故数字整体取代旧版:

| 项 | 旧版(debug) | 本轮(release,可信) | 说明 |
|---|---|---|---|
| 构建 | debug(opt-level 0) | **release(opt-z + LTO,出货)** | debug 下优化机器码没被优化,perf 失真 |
| CPU 采样 | 单 3s 窗口 | **中位数 + 唤醒屏幕** | 旧法偶发误录 6%/18% |
| endless CPU | "~7×" | **~2.7×** | 旧 7× 是采样失真 |
| 跨游戏内存 | "33%→61% 递增" | **一致 ~40%** | 递增叙事不成立 |
| canvasmark 内存 | Migo 更差(泄漏) | **Migo 更好(泄漏已修)** 🎉 | |
| 重载 stress | "Migo ~1.9× 强" | **⚠️ Migo 落后(回归,待修)** | >2 万精灵 |
