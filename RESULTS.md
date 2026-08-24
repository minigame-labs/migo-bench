# migo-bench 对比结果

> 中文为默认版本;英文见 [RESULTS.en.md](RESULTS.en.md)。
> 原始数据:`out/results.csv`(稳态)、`out/stress_*.csv`(压力曲线)。每行都带完整溯源(Migo 版本、设备、WebView 版本、时间戳、`fps_source`)。
> **被测 Migo 构建:`release-tag:v0.9.4`** —— 发布页上能下载的那个 AAR,不是某个 master 提交。
> 上一版本页锚定的是「master(v0.9.3 之后)」,任何人都复现不出来;2026-08-25 已按本页自己
> 写下的计划重测并改回 tag 溯源。原始数据 `out/matrix.csv`(18 行,三轮交错,逐格温控门结论
> 随行记录),归约口径由 `scripts/matrix-summary.py` 固定(中位数 + 保留区间)。
> 测试构建:Migo **release**(opt-z + LTO,出货配置),宿主配置与出货一致(`setDebugEnabled(false)`)。
> **本页数据于 2026-08-25 全量重测(v0.9.4)。** 与 08-23 那一版存在两处差异,读之前要知道:
>
> 1. **装置修了一处,数字因此可比性变了。** 采集脚本此前**每次运行前都 `adb install`**,
>    而本页方法学第 2 条写的是轮次之间不要装 —— 那条规矩从来没有真正生效过,一行都没有。
>    install 会重置 ART profile,紧随其后的启动跑的不是稳态 AOT 代码,正是 §5.2.1 里那次
>    把 WebView 首帧写成 522 ms 的机制。现在只在 APK 内容真的变了时才装,并在矩阵开跑前
>    各跑一次丢弃。实测把 WebView 的 bunnymark 首帧读数从 375 拉回 345 ms。
>    **所以本页与上一版的差异不只是版本差异,还有方法学差异。**
> 2. **`endless-runner` 的可玩耗时方向变了,现在是我们输**,见 §1。原因尚未查明,不做解释。

> **另一份报告:[JITLESS.md](JITLESS.md)** —— 无 JIT 的 V8 要付多少代价(HarmonyOS NEXT 禁止
> 第三方 JIT,那份数据决定 NEXT 能不能谈性能)。它和本页是两个问题:本页比的是 Migo 与
> WebView,那页比的是同一个 Migo 的两种 V8 配置。

## 1. 结论先行

同一游戏、同一设备、同一交互,**Migo 原生运行时(release)** vs **Android 系统 WebView**。定位:Migo = 源码可得的原生 WebView 替代。

- ✅ **内存:Migo 少 49–62%**(bunnymark 108 vs 236、endless-runner 201 vs 390、canvasmark 86 vs 225 MB)。公平口径:WebView 计入独立的 chromium 渲染进程(否则少算 ~100MB)。
- ✅ **CPU:Migo 用 WebView 的 1/3 到 1/2(2.5–2.9×)**——bunnymark 2.8×、endless-runner 2.9×、canvasmark 2.5×。
- ✅ **启动:六项里五项更快。** 首帧三款全胜(快 7% / 36% / 53%),可玩两胜一负
  (bunnymark 快 23%、canvasmark 快 34%、**endless-runner 慢 10%**)。
  上一版写的是"六项全部更快",现在不成立。
- = **帧率:打平。** 两侧中位数都是 60 fps;1% 低帧 Migo 59、WebView 60。
- = **重载扩展性:打平。** 压到 220,000 精灵,拐点两边都在 40,000,曲线逐档持平或 Migo 高 1 fps。
- 🔴 **`endless-runner` 的可玩耗时:上一版说"略快",本版是慢 10%。** Migo 三轮
  726/736/686 ms,WebView 662/819/640 ms。**Migo 的读数很稳(区间 50 ms),WebView 很不稳
  (区间 179 ms)**,所以差值本身要谨慎读 —— 但 Migo 自己的区间与上一版的 609/577/695
  几乎不重叠,这更像是我们变慢了,而不是测量噪声。
  **原因仍未查明,但已经排除了两条,并且发现这一格本身比看上去更不稳:**
  - ❌ **不是启动快照。** 曾怀疑 #119 重新生成的快照,当场用 `migo_log_level=info` 验掉了:
    日志明确是 `using V8 startup snapshot (2167504 bytes)` / `snapshot=true`,快照正常加载。
  - ✅ **不是 module evaluation 在乱跳** —— 这一条是本页短暂写错过又改回来的。先看到同一构建
    连跑两次是 265.7 / 196.1ms,便写成"波动 70ms";补跑六次后分布是
    **225.8 / 199.0 / 197.7 / 202.6 / 199.8 / 197.9ms** —— 去掉长时间空闲后的首跑,
    其余五次落在 197.7–202.6(摆幅 5ms),**相当稳**。那 70ms 是"空闲后首跑 vs 热跑"的差,
    不是内在波动。两个点不构成分布,这是本页第二次被这件事教训(§5.1 那条撤回的温度结论
    也只测过一次)。
  - ⚠️ 但这也意味着**冷态下的首跑确实更贵**(225–266ms vs 热态 199ms),而本页每一格都
    经过温控门、也就是每一格测的都是那种首跑。跨版本比较因此是成立的,只是它比较的是
    冷启动而不是稳态。
  - 📌 **附带发现(只影响这一个游戏)**:endless-runner 每次启动会触发两次
    `canvas2d force_readback_snapshot`,各阻塞 V8 15–17ms,合计约 30ms。
    bunnymark 与 canvasmark 各 0 次。这是 Phaser 走 `getImageData().data` 做纹理时的
    同步 GPU 回读;机制清楚,但修它要动 canvas2d 回读管线,不在本次范围内。

> 注意:目前仅测过高端机(麒麟 990)。中低端机的内存/启动差距预计更大——是下一步测试重点。

## 2. 测试矩阵(设备 × 游戏)

| 设备档位 \ 游戏 | bunnymark (Pixi/WebGL) | endless-runner (Phaser/WebGL) | canvasmark (Canvas2D) |
|---|---|---|---|
| **高端** · 华为 Mate30 Pro(麒麟990/8G/Android 12) | ✅ 已测 | ✅ 已测 | ✅ 已测 |
| **中端**(~4G) | 🔜 | 🔜 | 🔜 |
| **低端** ⭐(~2-3G) | 🔜 | 🔜 | 🔜 |

> 1 设备 × 3 游戏(两条渲染路径:WebGL × 2 + Canvas2D × 1),真机渲染逐一核对满屏正确。

## 3. 分游戏结果

每格为**三轮交错测量的中位数**(见 §5.2);每轮内 WebView 与 Migo 背靠背跑同一款游戏。

### 3.1 bunnymark(Pixi/WebGL)

| 指标 | WebView | Migo | 差异 |
|---|---|---|---|
| PSS 内存峰值 | 225 MB | 111 MB | Migo 少 51% |
| CPU(多核) | 127% | 46% | Migo 2.8× 少 |
| 首帧(`Displayed`) | 354 ms | 218 ms | Migo 快 38% |
| 可玩(`Fully drawn`) | 529 ms | 397 ms | Migo 快 25% |
| fps 中位 / 1% low | 60 / 60 | 60 / 59 | 打平 |

### 3.2 endless-runner(Phaser/WebGL)

| 指标 | WebView | Migo | 差异 |
|---|---|---|---|
| PSS 内存峰值 | 379 MB | 201 MB | Migo 少 47% |
| CPU(多核) | 134% | 44% | Migo 3.0× 少 |
| 首帧 | 350 ms | 286 ms | Migo 快 18% |
| 可玩 | 647 ms | 609 ms | 略快(区间偏宽,见 §1) |
| fps 中位 / 1% low | 60 / 60 | 60 / 59 | 打平 |

WebView 竖屏 fit-scale、Migo 原生横屏(按 game.json)——两边均渲染整局、像素预算相同。

### 3.3 canvasmark(Canvas2D)

| 指标 | WebView | Migo | 差异 |
|---|---|---|---|
| PSS 内存(稳) | 220 MB | 85 MB | Migo 少 61% |
| CPU(多核) | 171% | 74% | Migo 2.3× 少 |
| 首帧 | 353 ms | 219 ms | Migo 快 38% |
| 可玩 | 376 ms | 326 ms | Migo 快 13% |
| fps 中位 / 1% low | 60 / 60 | 60 / 59 | 打平 |

Canvas2D 路径两侧都比 WebGL 更吃 CPU,因此 CPU 领先幅度比另外两款小,属正常现象。

## 4. 重载下的扩展性

用游戏内确定性精灵 ramp 把负载推到 220,000 精灵(远超任何真实小游戏),每档冷却门控到同一起始温度后各跑两次:

| 精灵数 | WebView fps(两次) | Migo fps(两次) | Migo/WebView |
|---:|---:|---:|---:|
| 40 000 | 60 / 60 | 60 / 60 | 1.00× |
| 70 000 | 43 / 42 | 44 / 45 | 1.05× |
| 100 000 | 31 / 31 | 32 / 32 | 1.03× |
| 140 000 | 23 / 23 | 23 / 23 | 1.00× |
| 180 000 | 16 / 16 | 17 / 17 | 1.06× |
| 220 000 | 13 / 13 | 13 / 13 | 1.00× |

两边掉到 55fps 以下的拐点都在 40,000 精灵。**结论是打平**,Migo 在三档上高 1 fps。

**一条此前的声明已撤回。** 本页曾写"Migo 在 220k 时机身更凉(62.4 vs 66.1°C),因为它把负载分摊到三个 CPU 集群而 WebView 顶死大核"。2026-08-23 重测复现不出来:两侧 SoC 峰值分别为 WebView 62.5/64.6°C、Migo 64.2/65.1°C,Migo 略高;频率采样显示两次运行 governor 都把集群拉到了 2861 MHz。原声明只测过一次,这次撤回。

## 5. 测量方法(系统级、app 无关、可审计)

### 5.1 2026-08-23 修正的三处口径问题

在这次重测之前,两侧测的不完全是同一件事。三处都已修正,方向不同:

1. **可玩耗时的信号不同源(对 Migo 有利)。** WebView 侧由游戏自己在首帧调 `AndroidBench.ready()`;Migo 侧用的是引擎的 `onGameReady`,它在**模块求值结束、首帧之前**触发。实测这两点相差 **32 ms**。现在两侧都由游戏的同一行代码触发——migo shell 用前置脚本注入同名的 `AndroidBench`,经 `gameLog` 通道回到宿主。
2. **shell 结构不对称(对 Migo 不利)。** Migo shell 是两个 Activity,并且**每次启动都把整个游戏包从 assets 拷到 filesDir**;WebView shell 是一个 Activity,直接从 `file:///android_asset/` 读。测量窗口里因此多了一次 Activity 跳转和一次全量拷贝。现在两侧各一个 Activity,解包改为按游戏版本一次(真实宿主也是安装/下载时解一次,不是每次启动重解)。
3. **Migo 跑在 debug 配置下(对 Migo 不利)。** `setDebugEnabled(true)` 会注册一个 WebView 侧没有对应物的 console 环形缓冲。现已关闭,与出货配置一致。

`setCodeSigningEnabled(false)` 保留:WebView 除 APK 签名外本就不做逐文件校验,只在一侧开启等于测一个对方没有的功能。

### 5.2 交错测量(为什么不能跨时段比)

设备状态会随时间漂移。同一份未改动的 WebView shell,在一夜的测试中读数在 **380–524 ms** 之间变动——不是热节流(SoC 36.9°C、电池 34°C),而是设备状态的慢漂移。**任何跨时段的 A/B 都不可信。**

本页所有稳态数字都用交错测量:每个游戏 WebView 与 Migo 背靠背各跑一次为一轮,共三轮,取每格的中位数。压力曲线另有温度门(§4)。

### 5.2.1 刚安装的 APK 不是稳态(2026-08-23 修正)

本页 2026-08-23 之前发布的 bunnymark 启动数字**高估了 WebView**:首帧写的是 522 ms、可玩 650 ms,
重测的稳态是 354 / 529 ms。差了 170 / 120 ms,方向对 Migo 有利。

原因是那一轮的 WebView shell 刚 `adb install` 完就开测。新装的 APK 还没做 dex 优化,
头几次冷启动明显更慢,而且是**单调下降**而不是围绕均值抖动:重装后连测六次读到
414 → 371 → 347 → …,再往后稳定在 338–360。交错测量能消掉设备的慢漂移,消不掉这个,
因为它只作用在一侧——那一轮只有 WebView shell 是新装的。

所以口径补一条:**测量前两个 shell 都必须已安装并各跑过至少三次**,读数稳定后才开始记。
安装动作本身也不要夹在两次测量之间——写一个 361 MB 的 APK 会扰动紧随其后的那次冷启动。

### 5.3 各项口径

- **内存**:`dumpsys meminfo`,WebView 求和主进程 + `:sandboxed_process`。
- **启动**:系统 `am` 的 `Displayed` + `Fully drawn`,不解析 app 日志。首帧(`Displayed`)对 WebView 是空白窗口先绘制,两侧含义不同,但两个数都列出。
- **帧率**:优先 SurfaceFlinger `--latency`;个别设备(如本轮测试机所在的 EMUI)会屏蔽该接口(全 0),此时回退到游戏自身的 rAF 遥测(两侧同源),每行数据记录 `fps_source`。
- **CPU**:`/proc/<pid>/stat` 增量(WebView 含渲染进程);取多窗口中位数。
- **朝向**:WebView 锁竖屏;Migo 按 game.json 原生朝向——两边均渲染整局、像素预算相同。
- **稳定性**:采集前强制亮屏(`svc power stayon`)。

## 6. 集成成本(用户从不打开小游戏时,宿主付出什么)

最小宿主 App,三种集成方式,单 ABI(arm64-v8a),Mate30 Pro,五次冷启动中位数:

| 集成方式 | APK 净增 | 宿主冷启增量 | 常驻内存增量 |
|---|---:|---:|---:|
| 不带 Migo(基线) | — | 280 ms | 35.4 MB |
| 完整 AAR | **+44.8 MB** | **0 ms**(277 ms) | **+1.1 MB**(36.5 MB) |
| 完整 AAR + 宿主调用 `MigoRuntime.getInstance()` | +44.8 MB | **0 ms**(278 ms) | +1.1 MB |
| `-nojni` AAR(引擎按需下载) | **+0.23 MB** | **0 ms**(280 ms) | +1.1 MB |

- APK 净增是**磁盘上的**大小(`.so` 在 APK 里不压缩存储);商店**下载**增量约 +17 MB。
- 冷启增量为零、常驻内存只增约 1 MB(即 SDK 那点 dex),是因为引擎在第一次真正需要之前不会被加载——即使宿主已经拿到了 `MigoRuntime` 实例。
- `-nojni` 是同一次构建删掉 `jni/**` 得到的产物,引擎在用户第一次打开小游戏时由宿主交付并按内嵌 manifest 校验。

## 7. 已知局限 / 下一步

- 目前只测过一台高端设备(华为 Mate30 Pro,麒麟 990)。中端与低端设备是下一步核心测试。
- 功耗目前用 CPU 占用作代理(测试机的电量统计接口受限);真实功耗待换用无此限制的设备或外接功率计验证。
- 绝对数值会随设备状态浮动;本页给出的是同轮次、背靠背的相对对比(§5.2)。
- endless-runner 的可玩耗时在噪声内,不应作为领先项引用(§1)。

## 8. 复现

```bash
export PATH=$PATH:$ANDROID_HOME/platform-tools
# Migo release AAR(出货配置):scripts/build-aar.sh release arm64-v8a(在 migo 仓库里)

# 交错测量:每轮内两侧背靠背,重复三轮后取每格中位数(§5.2)
for round in 1 2 3; do for g in bunnymark canvasmark endless-runner; do
  bash scripts/run.sh --runtime webview --game $g --device <SERIAL> --duration 12 --cold-runs 3
  bash scripts/run.sh --runtime migo    --game $g --device <SERIAL> --duration 12 --cold-runs 3 \
       --migo-aar <path/to/migo-release.aar>
done; done
python3 scripts/compare.py --results out/results.csv --game bunnymark --vs-webview

# 控温 stress A/B(冷却门到同温冷态 + 三 cluster 频率采样 + 各跑 2 次;见 §4):
bash scripts/stress-ab.sh <SERIAL> <path/to/migo-release.aar>
```

基线快照:`baselines/mate30.csv`。
