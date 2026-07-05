# migo-bench 对比结果

> 中文为默认版本；英文见 [RESULTS.en.md](RESULTS.en.md)。
> 原始数据:`out/results.csv`(稳态)、`out/stress_*.csv`(压力曲线)。每行都带完整溯源(Migo 版本、设备、WebView 版本、时间戳、`fps_source`)。

## 1. 结论先行

同一游戏、同一设备、同一交互,在 **Migo 原生运行时** 与 **Android 系统 WebView** 上对比。定位:Migo = 开源原生的 WebView 替代。**头条是一致性 + 可审计 + 内存/CPU 效率;帧率通常打平,从不夸大。**

- ✅ **内存:Migo 明显更省**(~147MB vs WebView ~222MB,**少约 34%**)——关键:WebView 的渲染跑在**独立的 chromium 进程**里,必须把它算进去才公平(否则少算 ~100MB)。
- ✅ **CPU:Migo 约为 WebView 的一半**(~47% vs ~120%,同样 100 精灵 60fps)——原生 GL 比 Chromium 合成器更省 CPU;这也是功耗的代理指标。
- ✅ **重载吞吐:Migo 明显更强**——精灵数拉到 4 万以上两侧分化,10 万精灵 Migo 32fps vs WebView 17fps(**~1.9×**)。
- ✅ **启动抗压:热机下 Migo 更快**——凉机游戏就绪基本持平(506 vs 528ms),但连续跑热/降频后 Migo 506ms vs WebView 1242ms(**~2.4×**),WebView 的 Chromium 冷启动被降频严重放大。
- = **帧率(常规负载):打平**(都 ~60fps)。
- ✅✅ **游戏越重,差距越大**——换成真实的 Phaser 游戏 endless-runner,内存差从 33% 拉大到 **61%**、CPU 从 ~2.6× 拉大到 **~7×**(Migo 原生开销近乎固定,WebView 的 Chromium 税随应用增长)。见 §3.6。
- ⚠️ **诚实反例(Canvas2D)**——第三款游戏 canvasmark 走 Canvas2D 路径:Migo **CPU 仍赢一半、帧率打平**,但**内存反而更高更抖**(~150–285MB 锯齿 vs WebView 稳 ~221MB)。这是本框架 bisect 定位出的一个**真实 Migo GPU 资源泄漏**(每次 Canvas2D fill 绘制泄漏 ~400B 被锁定的 GL 资源),不回避。见 §3.7。

> 注意:这是**高端机**(麒麟 990)。多数指标 Migo 已占优;GTM 楔子市场是**低端机**(内存小、易降频),内存/启动/重载差距预计更大——低端机是下一步的核心测试(见矩阵)。

## 2. 测试矩阵(设备 × 游戏)

| 设备档位 \ 游戏 | bunnymark (Pixi/WebGL) | endless-runner (Phaser/WebGL) | canvasmark (Canvas2D) |
|---|---|---|---|
| **高端** · 华为 Mate30 Pro(麒麟990/8G/A12) | ✅ 已测 | ✅ 已测 | ✅ 已测 ⚠️ |
| **中端**(~4G,待采购) | 🔜 | 🔜 | 🔜 |
| **低端** ⭐(~2-3G,待采购,GTM 楔子) | 🔜 | 🔜 | 🔜 |

> 目前 1 台设备 × 3 游戏已跑通(覆盖两条渲染路径:WebGL × 2 + Canvas2D × 1);矩阵随设备到位逐格填充。
> **交叉发现 1(WebGL)**:换成更重、更真实的 Phaser 游戏,Migo 领先不缩反**大幅拉大**(内存差 33%→61%,CPU ~2.6×→~7×)——见 §3.6。
> **交叉发现 2(Canvas2D,诚实反例 ⚠️)**:canvasmark 上 Migo **CPU 仍赢约一半、帧率打平,但内存反而更高**——根因(已 bisect 定位)=Migo Canvas2D **每次 fill 绘制泄漏一个被锁定的 GL 资源**,内存抖到 ~2× WebView,是本框架挖出的一个真实 Migo GPU 泄漏——见 §3.7。

## 3. 结果:Mate30 Pro × bunnymark(100 精灵,60s 稳态)

### 3.1 内存 🏆 Migo

| 指标 | WebView | Migo | 差异 |
|---|---|---|---|
| PSS 峰值 | **~222 MB** | **~147 MB** | **Migo 少 ~34%** |

- **公平口径**:WebView = 主进程 + chromium 沙箱渲染进程之和(`dumpsys meminfo <pkg>` 只算主进程,会漏掉渲染进程约 100MB)。Migo 是**单进程**,全部计入。
- PSS 有 ±几十 MB 抖动(GC/系统状态);多轮平均会更稳,方向(Migo 明显更省)稳健。

### 3.2 启动:凉机持平,热机 Migo 更抗压 🏆

**游戏就绪(系统 `Fully drawn`,游戏首个真实帧 → `reportFullyDrawn()`,公平口径):**

| 设备状态 | WebView | Migo | |
|---|---|---|---|
| **凉机(fresh)** | 528 ms | 506 ms | ≈ 持平,Migo 略快 |
| **热机/降频(连续跑数小时后)** | **1242 ms** | **506 ms** | **Migo ~2.4× 快** |

- 凉机基本持平(V8 快照抵消原生初始化)。**热机下 WebView 的 Chromium 冷启动(进程拉起 + 页面加载 + JS 初始化,CPU 密集)被降频严重放大,而 Migo 的快照恢复几乎不受影响**——热机/降频正是**低端机 + 长时间游玩**的常态,这是对 Migo 有利的真实场景。
- "首帧(`Displayed`)"对 WebView 是空白窗口先绘制、偏早,两侧口径不一,**以"游戏就绪"为准**;Migo 还多一层 Launcher→Game 跳转。

### 3.3 帧率 = 打平

| 指标 | WebView | Migo |
|---|---|---|
| fps 中位 | 60 | 59 |
| 1% low | 60 | 57 |

**压力曲线(游戏内确定性 ramp 到 20 万精灵,`--scenario stress`)—— 重载下 Migo 明显更强 🏆**:

| 精灵数 | WebView fps | Migo fps | Migo 倍率 |
|---:|---:|---:|:---:|
| ≤20 000 | 60 | 59–60 | 打平 |
| **40 000** | 40 | **59** | Migo 仍 60,WebView 已掉 |
| **70 000** | 25 | **45** | ~1.8× |
| **100 000** | 17 | **32** | ~1.9× |
| 140 000 | 13 | 23 | ~1.8× |
| 180 000 | 10 | 17 | ~1.7× |
| 220 000 | (掉出) | 13 | Migo 仍在跑 |

≤2 万精灵两侧都 60fps(高端机天花板远在其上);**过了 2 万,原生 GL 的 Migo 明显更抗压**:40k 处 Migo 还 60、WebView 已掉到 40;100k 处 Migo 32 vs WebView 17(**~1.9×**)。WebView 拐点在 ~2–4 万,Migo 在 ~4–7 万。这是 ≤2 万时被掩盖的真实吞吐差距。

### 3.4 CPU 🏆 Migo

| 指标 | WebView | Migo | 差异 |
|---|---|---|---|
| CPU 占用(多核,可 >100%) | **~120%** | **~47%** | **Migo ~一半以下** |

- 口径:`/proc/<pid>/stat` 的 (utime+stime) 增量;WebView 计入主进程 + chromium 渲染进程(与内存同理)。
- 同帧率下 Migo CPU 约为一半 → 更省电(见功耗)。单次采样,多轮会更稳。

### 3.5 功耗(代理)

真机功耗直接测量在本机受限:该 EMUI 设备**关闭了 fuel gauge**(`current_now` 不可读)且 **per-uid batterystats 能量模型不可用**,加上 USB 供电会掩盖电池放电。**当前以 CPU 占用作为功耗代理**(定帧率下 CPU 是主要功耗驱动)→ Migo 更省。
真·功耗待:①非华为设备(开放 fuel gauge)②断电跑 + 电量差 ③外接功率计。

## 3.6 第二款游戏:endless-runner(Phaser)—— 差距随游戏变重而拉大 🏆🏆

第二款游戏用的是 **Phaser 3** 引擎的完整 webpack 打包产物(真实小游戏,不是合成基准),同设备、同口径、45s 稳态:

| 指标 | WebView | Migo | 差异 |
|---|---|---|---|
| **PSS 峰值** | **~378 MB** | **~146 MB** | **Migo 少 ~61%** |
| **CPU(多核)** | **~125%** | **~18%** | **Migo ~WebView 的 1/7** |
| 游戏就绪(`Fully drawn`) | 654 ms | 631 ms | ≈ 持平 |
| fps 中位 / 1% low | 60 / 60 | 60 / 57 | 打平 |
| fps 来源 | game-telemetry | game-telemetry | 两侧同源(EMUI 屏蔽 SurfaceFlinger) |

**跨游戏对比(这才是重点):**

| 指标 | bunnymark(轻,合成) | **endless-runner(重,真实 Phaser)** |
|---|---|---|
| 内存(Migo vs WebView) | 147 vs 222 MB → 少 34% | **146 vs 378 MB → 少 61%** |
| CPU | 46% vs 122% → ~2.6× | **18% vs 125% → ~7×** |
| 游戏就绪 | 506 vs 528 → 持平 | 631 vs 654 → 持平 |
| fps | 60 / 60 | 60 / 60 |

**结论**:换成更重的真实游戏,Migo 的领先**不是缩小而是拉大**。原因:**Migo 原生运行时的开销近乎与游戏无关**(146MB ≈ bunnymark 的 147MB;CPU 甚至更低,因为这游戏动的对象比 100 只兔子少),是一层**固定的低底噪**;而 **WebView 的 Chromium 税随应用变重而增长**(内存 222→378MB,CPU 高位不降)。也就是说 —— **游戏越真实、越重,Migo 的优势越明显**,这正是真实小游戏(而非玩具基准)所处的区间。

> 单轮采样(与 bunnymark 的 CPU/内存同口径),方向差距极大、稳健;绝对值多轮平均会更稳。endless-runner 的 fps 遥测用的是**引擎无关的 rAF 计数器**(两侧注入完全相同的代码,`[endless-runner] fps=N`),WebView 的"游戏就绪"由注入的 `AndroidBench.ready()` 首帧回调触发、Migo 由原生 onGameReady 触发 —— 这就是新游戏接入本框架要满足的**遥测契约**。

## 3.7 第三款游戏:canvasmark(Canvas2D)—— 诚实的反例 ⚠️

第三款游戏走**另一条渲染路径**:纯 Canvas 2D(不是 WebGL)。canvasmark 是 bunnymark 的 2D 版——每帧 `save/translate/rotate/fillRect` 画 N 个旋转方块(canvas2d 热路径),tap 加精灵,同样 100 起步。**先说好消息:Migo 原生实现了 Canvas2D(Skia 支撑),`getContext('2d')` 是真的 2D 上下文,60fps 渲染没问题**——所以"WebView 替代"覆盖 2D canvas 游戏,不止 WebGL 引擎。

| 指标 | WebView | Migo | 读法 |
|---|---|---|---|
| CPU(多核) | **173%** | **89%** | **Migo ~一半** ✅(Canvas2D 在两侧都比 WebGL 更吃 CPU,但 Migo 仍省一半) |
| fps 中位 / 1% low | 60 / 60 | 60 / 58 | 打平 ✅ |
| 游戏就绪 | 380 ms | 450 ms | WebView 略快 ~18% |
| **PSS 内存** | **~221 MB(稳)** | **~150–285 MB(抖动)** | **⚠️ Migo 更差** |

**反例发现(本框架的价值所在)**:canvasmark 上 **Migo 内存反而更高且不稳**。100 精灵、无交互下,Migo 的 PSS 锯齿式在 ~150–285MB 之间涨-回收(~3MB/s 涨,周期性 purge),WebView 稳在 ~221MB。**已用本框架系统 bisect 定位根因**:

| 探针 | 每帧 fill 数 | 每帧换色 | 40s 内 GL 内存 |
|---|---|---|---|
| 只画背景 | 1 | ~0 | **平,18MB** |
| 100 fill,无变换 | 101 | ~100 | 46→130MB |
| 100 fill,固定色 | 101 | 2 | 37→122MB |

- 增长**全在 GPU 图形内存(`dumpsys meminfo` 的 `GL mtrack`)**,Java/Native 堆纹丝不动 → **不是 JS/GC 堆**(我最初以为是 JS `save/restore` 分配,真机实测证伪)。
- 泄漏**只随每帧 fill 绘制次数线性增长**(与颜色、旋转/变换、present 均无关)→ **每次 Canvas2D fill 绘制泄漏 ~400 字节 GL 资源**。
- 这些资源**被锁定引用、Skia 清理 purge 不掉**(把每帧 deferred-cleanup 调到 0ms 激进 purge 也无效)→ 是 **Migo Canvas2D 渲染路径的真实 GPU 资源泄漏**(每次 draw 留下一个不释放的 GPU 引用),不是缓存抖动、也不是 GC 问题。

**这正是 benchmark 该干的事**:不是给 Migo 唱赞歌,而是诚实定位**Migo 哪条路径要优化**。结论:**WebGL 路径 Migo 全面领先(越重越大);Canvas2D 路径 Migo 赢 CPU、平帧率,但有一个真实的 per-draw GPU 资源泄漏待修**。修好后重跑 canvasmark,GL 内存转平 = 本框架回归门正好验证修复(见 README「Regression workflow」)。fps 全程 60 不受影响。

> 已定位到"每次 fill 绘制泄漏被锁定的 GL 资源",但精确的持有引用点需要更深的 render-engine 代码考古 + GPU 工具,未在本轮修复(不做无根据的猜测式修改)。fps 遥测=游戏自带 rAF 计数器 `[canvasmark] sprites=N fps=M`(两侧同源)。

## 4. 测量方法(系统级、app 无关、可审计)

- **内存**:`dumpsys meminfo`,WebView 求和主进程 + `:sandboxed_process`(`webview_pss.py`)。
- **启动**:系统 `am` 的 `Displayed`(首帧)+ `reportFullyDrawn`/`Fully drawn`(游戏就绪);不解析 app 日志。
- **帧率**:优先 `dumpsys SurfaceFlinger --latency`(合成器真实呈现时间戳,app 无关);**本设备 EMUI 屏蔽了该接口(全 0)**,回退到游戏自身 fps 遥测(两侧同源、对称),每行记 `fps_source`。非华为机会用 SurfaceFlinger。
- **CPU**:`/proc/<pid>/stat` 增量(WebView 含渲染进程)。
- **压力**:游戏内确定性精灵 ramp(Pixi ticker,两侧一致;`make-stress-game.sh` 生成),fps 对精灵数作曲线。
- **稳定性护栏**:采集前强制亮屏保持(`svc power stayon`)——熄屏会导致 activity 停止、零帧零数据。
- **启动时间解析**:ActivityManager 的 `Displayed/Fully drawn` 在 <1s 时是 `+868ms`、≥1s 时变成 `+1s43ms`——解析必须处理秒/分单位(否则慢启动/低端机全被丢空)。
- **热节流提示**:连续跑数小时后麒麟 990 会降频(冷启动可慢 2–3×)。同一轮里两侧**背靠背**测,相对对比仍公平;绝对值需凉机复现。低端机本就更易降频,这也是真实场景。

## 5. 复现

```bash
export PATH=$PATH:$ANDROID_HOME/platform-tools
# 稳态:
bash scripts/run.sh --runtime webview --game bunnymark --device <SERIAL> --duration 60 --cold-runs 3
bash scripts/run.sh --runtime migo    --game bunnymark --device <SERIAL> --duration 60 --cold-runs 3 --migo-aar local:.../migo-debug.aar
# 压力曲线:
bash scripts/run.sh --runtime migo    --game bunnymark --device <SERIAL> --scenario stress --duration 48 --migo-aar local:...
```

```bash
# 对比 / 回归门(Migo vs WebView 表 · 或新 Migo vs 基线):
python3 scripts/compare.py --results out/results.csv --game bunnymark --vs-webview
python3 scripts/compare.py --results out/results.csv --baseline baselines/mate30.csv --game bunnymark
```

Migo 版本可 pin:`--migo-aar local:PATH | release-tag:TAG | sha:SHA`——每个结果都钉在一个确切的 Migo 版本上(可审计)。基线快照在 `baselines/`,将来任何 Migo 优化重跑一遍即可 diff 出变好/变差(见 README「Regression workflow」)。
