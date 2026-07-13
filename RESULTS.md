# migo-bench 对比结果

> 中文为默认版本；英文见 [RESULTS.en.md](RESULTS.en.md)。
> 原始数据:`out/results.csv`(稳态)、`out/stress_*.csv`(压力曲线)。每行都带完整溯源(Migo 版本、设备、WebView 版本、时间戳、`fps_source`)。
> **本轮(2026-07 重跑)口径**:Migo 用 **release** 构建(opt-z + LTO,出货配置),取代此前发布的 debug 数字。**并修了两处渲染 bug 后重测**(见 §0),此前一版的 canvasmark(Migo 只渲染 1/9 屏)与 endless-runner(WebView 横屏空白)对比无效,已被本页取代。

## 0. 本轮修的两处渲染 bug(先说清楚)

对比要成立,两边必须**都把整个游戏正确渲染**。本轮真机核对发现并修复:

1. **Migo canvasmark 只渲染到左上角 ~1/9 屏**(Canvas2D 路径)。根因:surfaceChanged(状态栏区域变化)时引擎把 Canvas2D 的 backing 强制成物理尺寸,而 DPR-naive 游戏只在初始化读一次画布尺寸、之后一直按逻辑坐标画 → 画到超大 backing 的一角。WebGL 游戏每帧重读画布尺寸所以不受影响,之前 wx-way 修复只覆盖了 WebGL。**已修**(migo `fix/canvas2d-onscreen-backing-corner`:surface resize 时按比例保留 backing 的逻辑/物理选择)→ canvasmark 现在满屏,和 WebView 一致。
2. **WebView endless-runner 横屏渲染空白(只有天空)**。根因:bench 之前强制 WebView 横屏,旋转在 Phaser 定好画布尺寸之后发生,世界被留在屏外。**已修**:WebView 锁竖屏(浏览器本就在设备自然朝向跑,Phaser 把横屏游戏 fit-scale 进竖屏)。Migo 小游戏运行时按 game.json 原生横屏——朝向不同但两边都正确渲染整局、像素预算相同。

修复后三游戏两边都满屏/正确渲染(真机逐一核对)。以下是修复后的数字。

## 1. 结论先行

同一游戏、同一设备、同一交互,**Migo 原生运行时(release)** vs **Android 系统 WebView**。定位:Migo = 开源原生的 WebView 替代。

- ✅ **内存:Migo 明显更省,三款游戏一致 ~40–44%**(bunnymark 132 vs 227、endless-runner 226 vs 382、canvasmark 118 vs 212 MB)。公平口径:WebView 计入独立的 chromium 渲染进程(否则少算 ~100MB)。
- ✅ **CPU:Migo 用 WebView 的 1/2 或更少(~1.9–2.9×)**——bunnymark 2.6×、endless-runner 2.9×、canvasmark 1.9×。原生 GL/Skia 比 Chromium 合成器省 CPU;也是功耗代理。
- ✅ **启动:Migo 多数更快**——游戏就绪(`Fully drawn`)bunnymark 495 vs 697、canvasmark 473 vs 517 ms;endless-runner 710 vs 671(略慢 ~6%,单轮抖动范围内)。
- = **帧率(常规负载):近乎打平**——Migo ~58 vs WebView 60fps(Migo 1% low 略低),三款一致。
- 🎉 **canvasmark 的 Canvas2D 内存表现好**——上一版(debug)这里 Migo 内存锯齿到 285MB(一个 per-draw GL 资源泄漏);本轮 release + 满屏渲染下 Migo 稳定 118MB(< WebView 213MB),泄漏已不复现。
- ⚠️🔴 **优化引入的重载回归(诚实反例)**——合成压力拉到 2 万精灵以上,Migo 落后 WebView(10 万处 19 vs 32fps)。**"优化前后"A/B 证实这是本轮 R1/R2/R3 优化本身造成的真回归**:优化前的 ff29aa4 在同配置下 stress 明显更强(40k:59 vs 30;100k:32 vs 19),旧基线的 stress 数字是真的。瓶颈在 JS 侧,元凶最可能是 R2 命令流的 JS 侧每帧编码开销。见 §3.3、§7。

> 注意:高端机(麒麟 990)。常规负载多数指标 Migo 占优;低端机(GTM 楔子)内存/启动差距预计更大——下一步核心测试。

## 2. 测试矩阵(设备 × 游戏)

| 设备档位 \ 游戏 | bunnymark (Pixi/WebGL) | endless-runner (Phaser/WebGL) | canvasmark (Canvas2D) |
|---|---|---|---|
| **高端** · 华为 Mate30 Pro(麒麟990/8G/A12) | ✅ 已测 | ✅ 已测 | ✅ 已测 |
| **中端**(~4G,待采购) | 🔜 | 🔜 | 🔜 |
| **低端** ⭐(~2-3G,待采购,GTM 楔子) | 🔜 | 🔜 | 🔜 |

> 1 设备 × 3 游戏(两条渲染路径:WebGL × 2 + Canvas2D × 1),真机渲染逐一核对满屏正确。
> **跨游戏结论**:常规负载下 Migo 领先幅度三款高度一致(内存 ~40–44%、CPU ~1.9–2.9×),是一层稳定的低底噪优势,与游戏轻重基本无关。

## 3. 结果:Mate30 Pro × bunnymark(100 精灵,60s 稳态)

### 3.1 内存 🏆 Migo

| 指标 | WebView | Migo | 差异 |
|---|---|---|---|
| PSS 峰值 | **~227 MB** | **~132 MB** | **Migo 少 ~42%** |

- 公平口径:WebView = 主进程 + chromium 沙箱渲染进程之和(`webview_pss.py`)。Migo 单进程,全部计入。
- PSS 有 ±几十 MB 抖动;方向(Migo 明显更省)稳健。

### 3.2 启动 🏆 Migo

| 指标 | WebView | Migo | |
|---|---|---|---|
| 游戏就绪(`Fully drawn`,凉机) | 697 ms | 495 ms | Migo 快 ~29% |

- 口径:游戏首个真实帧 → `reportFullyDrawn()`。首帧(`Displayed`)对 WebView 是空白窗口先绘制、偏早,两侧不可比,以"游戏就绪"为准。
- 绝对值有热抖动(本轮 WebView 697 比上轮 536 慢,设备偏热);Migo 快照恢复更稳(495 ≈ 493)。

### 3.3 帧率:常规打平;重载 ⚠️ Migo 落后(根因=JS 侧)

**常规负载(100 精灵)**:fps 中位 WebView 60 / Migo 58;1% low 60 / 55。

**压力曲线(游戏内确定性 ramp,`--scenario stress`)—— ⚠️ >2 万精灵 Migo 落后**:

| 精灵数 | WebView fps | Migo fps |
|---:|---:|---:|
| ≤20 000 | 60 | 48–58 |
| 40 000 | 60 | 30 |
| 70 000 | 43 | 28 |
| 100 000 | 32 | 19 |
| 140 000 | 23 | 19 |
| 180 000 | 16 | 14 |

- **根因已用"优化前后"A/B 证实 = 这是优化本身引入的真回归(不是旧渲染伪数)**。把优化前的 ff29aa4 在同 release 配置重建重跑:**ff29aa4 的 stress 明显更强**(40k:59 vs 现在 30;100k:**32 vs 现在 19**),而且 ff29aa4 的 32@100k 和更早的旧基线完全吻合 → **旧基线"migo 赢 stress"是真的,现在的版本把它搞退步了**。
- **瓶颈在 JS 侧,元凶最可能是 R2 类型化命令流的 JS 侧每帧编码开销**。设备侧诊断(华为封了 `perf_event`,simpleperf 不可用,改用计数器):10 万精灵下 **Pixi 只发 6–7 个 GL 命令、渲染线程执行仅 5–8ms/帧**,整帧却 49–140ms → 渲染线程绝大部分在**等 JS 产帧**;逐线程 CPU 显示 **JS 线程 ~100%+ 独占**。R2 让每个 GL 调用先在 JS 侧编码进类型化命令流(最可能是把大顶点缓冲 `bufferSubData` 的 ~MB 级数据每帧复制进流),ff29aa4 没有 R2、直接原生调用,所以 JS 线程更轻、更快。渲染侧 R2 执行、wx-way 逻辑DB、R3 damage 均已被证据排除(都不是瓶颈)。
- **下一步**:逐个还原 R1/R2/R3 定位具体是哪一项(A/B 已证明是这几项的净效果,R2 嫌疑最大);或在非华为机上 profile JS 线程火焰图看 R2 编码占比。
- **下一步**:精确到 V8 内部原因需 profiling —— 本设备被华为封,需换非华为机跑 simpleperf 抓 JS 线程火焰图。
- 真实小游戏一般在数百~数千精灵(即常规负载,Migo 稳态占优);2 万+ 是合成极限。这条曲线是本框架该暴露的真实短板,不回避。

### 3.4 CPU 🏆 Migo

| 指标 | WebView | Migo | 差异 |
|---|---|---|---|
| CPU(多核) | **~118%** | **~46%** | **Migo ~2.6× 少** |

- 口径:`/proc/<pid>/stat` (utime+stime) 增量,WebView 含渲染进程。取多窗口中位数 + 采样前唤醒屏幕(消除偶发坏窗口)。

### 3.5 功耗(代理)

EMUI 关了 fuel gauge + per-uid batterystats 不可用 + USB 供电掩盖放电 → 以 CPU 作功耗代理(定帧率下 CPU 是主要功耗驱动)→ Migo 更省。真功耗待非华为机/断电/外接功率计。

## 3.6 第二款:endless-runner(Phaser)

| 指标 | WebView | Migo | 差异 |
|---|---|---|---|
| PSS 峰值 | **~382 MB** | **~226 MB** | **Migo 少 ~41%** |
| CPU(多核) | **~127%** | **~44%** | **Migo ~2.9× 少** |
| 游戏就绪 | 671 ms | 710 ms | 略慢 ~6%(抖动内) |
| fps 中位 / 1% low | 60 / 60 | 58 / 55 | 近乎打平 |

WebView 竖屏 fit-scale、Migo 原生横屏(见 §0),两边均渲染整局、像素预算相同。

## 3.7 第三款:canvasmark(Canvas2D)—— 修复渲染 bug 后的真实对比

Canvas2D 路径(非 WebGL)。**本轮修好了 Migo Canvas2D 只渲染 1/9 屏的 bug(见 §0)**,现在两边都满屏渲染,数字才可比:

| 指标 | WebView | Migo | 读法 |
|---|---|---|---|
| **PSS 内存** | **~213 MB(稳)** | **~118 MB(稳)** | **Migo 少 ~44% ✅** |
| CPU(多核) | **160%** | **83%** | **Migo ~1.9× 少** ✅(满屏渲染后差距比之前角落时的 2.4× 缩小=诚实值;Canvas2D 两侧都比 WebGL 吃 CPU) |
| fps 中位 / 1% low | 60 / 60 | 58 / 57 | 近乎打平 ✅ |
| 游戏就绪 | 517 ms | 473 ms | Migo 快 ~9% ✅ |

**内存泄漏已不复现**:上一版 debug 这里 Migo PSS 锯齿到 ~285MB(每次 Canvas2D fill 泄漏被锁的 GL 资源);本轮 release + 满屏渲染下 Migo 稳定 118MB(远低于 WebView 213MB)。fps 全程 ~58。

## 4. 测量方法(系统级、app 无关、可审计)

- **内存**:`dumpsys meminfo`,WebView 求和主进程 + `:sandboxed_process`。
- **启动**:系统 `am` 的 `Displayed` + `Fully drawn`;不解析 app 日志。
- **帧率**:优先 SurfaceFlinger `--latency`;本设备 EMUI 屏蔽(全 0)→ 回退游戏 rAF 遥测(两侧同源),每行记 `fps_source`。
- **CPU**:`/proc/<pid>/stat` 增量(WebView 含渲染进程);**多窗口中位数 + 采样前唤醒屏幕**(单窗口偶发会读出荒谬低值)。
- **压力**:游戏内确定性精灵 ramp(Pixi ticker,两侧一致)。
- **朝向**:WebView 锁竖屏(渲染正确);Migo 按 game.json(endless=横屏)——两边均满屏渲染整局,像素预算相同(见 §0)。
- **稳定性**:采集前 `svc power stayon` 强制亮屏。
- **热提示**:麒麟 990 连续跑会降频;两侧背靠背 + 游戏间 cooldown(本轮 32–35°C),相对对比公平,绝对值需凉机复现。

## 5. 复现

```bash
export PATH=$PATH:$ANDROID_HOME/platform-tools
# Migo release AAR(出货配置;bench 需可继承 API,release 需临时关 library minify):
#   scripts/build-aar.sh release arm64-v8a
bash scripts/run.sh --runtime webview --game bunnymark --device <SERIAL> --duration 60 --cold-runs 3
bash scripts/run.sh --runtime migo    --game bunnymark --device <SERIAL> --duration 60 --cold-runs 3 --migo-aar local:.../migo-release.aar
bash scripts/run.sh --runtime migo    --game bunnymark --device <SERIAL> --scenario stress --duration 55 --migo-aar local:...
python3 scripts/compare.py --results out/results.csv --game bunnymark --vs-webview
```

基线快照 `baselines/mate30.csv`(本轮 release + 渲染修复);旧 debug 基线备份 `baselines/mate30.debug-ff29aa4.bak.csv`。

## 6. 与旧版(debug / ff29aa4)差异

| 项 | 旧版(debug) | 本轮(release,渲染已修) |
|---|---|---|
| 构建 | debug(opt-0,失真) | **release(opt-z + LTO,出货)** |
| canvasmark 渲染 | Migo 只画 1/9 屏(未察觉) | **修好=满屏,对比才有效**;CPU 2.4×→**1.9×**(诚实) |
| endless-runner WebView | 被迫横屏=空白 | **锁竖屏=正确渲染** |
| CPU 采样 | 单 3s 窗口(偶发 6%/18%) | 中位数 + 唤醒屏幕 |
| 内存 | "33%→61% 递增" | **一致 ~40–44%** |
| canvasmark 内存 | Migo 更差(泄漏) | **Migo 更好(泄漏不复现,满屏下仍 −44%)** 🎉 |
| 重载 stress | Migo ~1.9× 强(**真实,非伪数**) | **⚠️🔴 优化本身搞退步了**(40k 59→30、100k 32→19);瓶颈 JS 侧,疑 R2 命令流 JS 编码。见 §7 |

## 7. 优化前后 A/B(NEW=8b5a704 含 R1/R2/R3 vs PREV=ff29aa4 优化前,同 release 配置、同设备、同 session)

为验证本轮优化(R1/R2/R3)到底有没有让性能变好,把优化前的 ff29aa4 在**同 release 配置**重建、真机重跑。**注意混淆**:ff29aa4 没有本轮渲染修复,三游戏都渲染成角落(画得少)→ CPU/内存不可直接比;**只有启动(冷启动)和 stress(JS 绑定)与渲染面积无关、可比**。

| 指标 | NEW(优化后) | PREV(优化前 ff29aa4) | 结论 |
|---|---|---|---|
| 启动 bunnymark | 495 ms | 516 ms | ✅ NEW 快 4%(可比) |
| 启动 endless | 710 ms | 763 ms | ✅ NEW 快 7%(可比) |
| 启动 canvasmark | 473 ms | 481 ms | ✅ NEW 快 2%(可比) |
| canvasmark PSS | **118 MB** | **297 MB** | ✅ NEW 修复了 Canvas2D 泄漏(297→118) |
| **stress 40k fps** | **30** | **59** | 🔴 **PREV 快 ~2×(优化退步)** |
| **stress 100k fps** | **19** | **32** | 🔴 **PREV 快 ~1.7×(优化退步)** |
| CPU / 其他内存 | — | — | ⚠️ 渲染面积混淆,不列 |

**结论(诚实、喜忧参半)**:
- ✅ **启动更快**(2–7%)——R1/快照等改善了冷启动。
- ✅ **canvasmark Canvas2D 泄漏修复**(297→118MB)——真实且重要的改进。
- 🔴 **重载吞吐明显退步**——优化前的 ff29aa4 在 stress 上明显更强(40k 处 fps 几乎翻倍)。这是本轮优化(最可能是 R2 类型化命令流的 JS 侧每帧编码开销)引入的**真回归**。这也**订正了本页早前版本**把 stress 归因为"V8 天生慢/旧数据是渲染伪数"的错误结论——A/B 证明旧基线是真的、退步是优化造成的。
- **净评价**:常规负载(数百~数千精灵)Migo 全面赢且启动更快、泄漏已修;但**优化在 2 万+ 精灵的极限压测下是净负**,需要回头优化 R2 的 JS 侧编码路径(避免每帧大顶点缓冲的多余复制)。
