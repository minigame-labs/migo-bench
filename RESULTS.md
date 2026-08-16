# migo-bench 对比结果

> 中文为默认版本；英文见 [RESULTS.en.md](RESULTS.en.md)。
> 原始数据:`out/results.csv`(稳态)、`out/stress_*.csv`(压力曲线)。每行都带完整溯源(Migo 版本、设备、WebView 版本、时间戳、`fps_source`)。
> 测试构建:Migo **release**(opt-z + LTO,出货配置)。

## 1. 结论先行

同一游戏、同一设备、同一交互,**Migo 原生运行时(release)** vs **Android 系统 WebView**。定位:Migo = 开源原生的 WebView 替代。

- ✅ **内存:Migo 明显更省,三款游戏一致 ~40–45%**(bunnymark 132 vs 227、endless-runner 226 vs 382、canvasmark 118 vs 213 MB)。公平口径:WebView 计入独立的 chromium 渲染进程(否则少算 ~100MB)。
- ✅ **CPU:Migo 用 WebView 的 1/2 或更少(~1.9–2.9×)**——bunnymark 2.6×、endless-runner 2.9×、canvasmark 1.9×。原生 GL/Skia 比 Chromium 合成器省 CPU;也是功耗代理。
- ✅ **启动:Migo 多数更快**——游戏就绪(`Fully drawn`)bunnymark 495 vs 697、canvasmark 473 vs 517 ms;endless-runner 710 vs 671(略慢 ~6%,单轮抖动范围内)。
- = **帧率(常规负载):近乎打平**——Migo ~58 vs WebView 60fps(Migo 1% low 略低),三款一致。
- ✅ **重载扩展性良好**——压测到 220,000 个精灵(远超真实小游戏的常规负载),Migo 全曲线与 WebView 打平、高载略胜,且运行更凉、负载分摊在多个 CPU 集群上,而非把单核顶到上限。详见 §4。

> 注意:目前仅测过高端机(麒麟 990)。常规负载下 Migo 占优;中低端机的内存/启动差距预计更大——是下一步测试重点。

## 2. 测试矩阵(设备 × 游戏)

| 设备档位 \ 游戏 | bunnymark (Pixi/WebGL) | endless-runner (Phaser/WebGL) | canvasmark (Canvas2D) |
|---|---|---|---|
| **高端** · 华为 Mate30 Pro(麒麟990/8G/Android 12) | ✅ 已测 | ✅ 已测 | ✅ 已测 |
| **中端**(~4G) | 🔜 | 🔜 | 🔜 |
| **低端** ⭐(~2-3G) | 🔜 | 🔜 | 🔜 |

> 1 设备 × 3 游戏(两条渲染路径:WebGL × 2 + Canvas2D × 1),真机渲染逐一核对满屏正确。
> **跨游戏结论**:常规负载下 Migo 领先幅度三款高度一致(内存 ~40–45%、CPU ~1.9–2.9×),是一层稳定的低底噪优势,与游戏轻重基本无关。

## 3. 分游戏结果

### 3.1 bunnymark(Pixi/WebGL,100 精灵,60s 稳态)

| 指标 | WebView | Migo | 差异 |
|---|---|---|---|
| PSS 内存峰值 | 227 MB | 132 MB | Migo 少 ~42% |
| CPU(多核) | 118% | 46% | Migo ~2.6× 少 |
| 游戏就绪(`Fully drawn`,凉机) | 697 ms | 495 ms | Migo 快 ~29% |
| fps 中位 / 1% low | 60 / 60 | 58 / 55 | 近乎打平 |

内存口径:WebView = 主进程 + chromium 沙箱渲染进程之和;Migo 单进程,全部计入。CPU 口径:`/proc/<pid>/stat` 增量,取多窗口中位数。

### 3.2 endless-runner(Phaser/WebGL)

| 指标 | WebView | Migo | 差异 |
|---|---|---|---|
| PSS 内存峰值 | 382 MB | 226 MB | Migo 少 ~41% |
| CPU(多核) | 127% | 44% | Migo ~2.9× 少 |
| 游戏就绪 | 671 ms | 710 ms | 略慢 ~6%(抖动内) |
| fps 中位 / 1% low | 60 / 60 | 58 / 55 | 近乎打平 |

WebView 竖屏 fit-scale、Migo 原生横屏(按 game.json)——两边均渲染整局、像素预算相同。

### 3.3 canvasmark(Canvas2D)

| 指标 | WebView | Migo | 差异 |
|---|---|---|---|
| PSS 内存(稳) | 213 MB | 118 MB | Migo 少 ~45% |
| CPU(多核) | 160% | 83% | Migo ~1.9× 少 |
| 游戏就绪 | 517 ms | 473 ms | Migo 快 ~9% |
| fps 中位 / 1% low | 60 / 60 | 58 / 57 | 近乎打平 |

Canvas2D 路径(非 WebGL)两侧都比 WebGL 更吃 CPU,因此这里的领先幅度比另外两款小,属正常现象。

## 4. 重载下的扩展性

常规负载(数百精灵,真实小游戏的典型量级)下两边帧率近乎打平。为了解每个运行时在极端负载下如何扩展,我们用游戏内确定性精灵 ramp 把负载一路推到 220,000 个精灵(远超任何真实小游戏),每档冷却门控到同一起始温度后各跑两次:

| 精灵数 | WebView fps(两次) | Migo fps(两次) | Migo/WebView |
|---:|---:|---:|---:|
| 40 000 | 60 / 60 | 58 / 59 | 0.97× |
| 70 000 | 41 / 43 | 45 / 45 | 1.07× |
| 100 000 | 31 / 31 | 32 / 32 | 1.03× |
| 140 000 | 22 / 22 | 23 / 23 | 1.05× |
| 180 000 | 15 / 16 | 18 / 17 | 1.13× |
| 220 000 | 13 / 13 | 13 / 13 | 1.00× |

两边掉到 55fps 以下的拐点都在 40,000 精灵左右。**Migo 全曲线与 WebView 打平、高载略胜**,并且是在更低的热代价下做到的:在 220k 这一极限点,WebView 把大核顶到接近满频(2855MHz)才勉强追平,而 Migo 把工作分摊到三个 CPU 集群(大/中/小核并行处理渲染、上传、JS),整机温度更低(SoC 尾值 62.4°C vs WebView 66.1°C)。

方法:两个运行时都用冷却门控制在同一起始温度(≤35°C、大核已恢复满频)才开跑,每秒采样三个 CPU 集群的频率与 SoC 温度,每档各跑两次以确认一致性。复现见 §7。

## 5. 测量方法(系统级、app 无关、可审计)

- **内存**:`dumpsys meminfo`,WebView 求和主进程 + `:sandboxed_process`。
- **启动**:系统 `am` 的 `Displayed` + `Fully drawn`;不解析 app 日志,以"游戏就绪"(`Fully drawn`)为准——首帧(`Displayed`)对 WebView 是空白窗口先绘制,两侧不可比。
- **帧率**:优先 SurfaceFlinger `--latency`;个别设备(如本轮测试机所在的 EMUI)会屏蔽该接口(全 0),此时回退到游戏自身的 rAF 遥测(两侧同源、口径一致),每行数据记录 `fps_source`。
- **CPU**:`/proc/<pid>/stat` 增量(WebView 含渲染进程);取多窗口中位数,并在采样前唤醒屏幕以避免偶发的坏窗口。
- **压力测试**:游戏内确定性精灵 ramp(Pixi ticker,两侧一致的驱动逻辑)。
- **朝向**:WebView 锁竖屏(浏览器按设备自然朝向渲染);Migo 按 game.json 原生朝向——两边均渲染整局、像素预算相同。
- **稳定性**:采集前强制亮屏(`svc power stayon`)。
- **热管理**:高负载下 SoC 会降频;两侧背靠背测试并在每局之间冷却,相对对比公平;绝对值会随设备热状态浮动。

## 6. 已知局限 / 下一步

- 目前只测过一台高端设备(华为 Mate30 Pro,麒麟 990)。中端与低端设备是下一步核心测试——预计内存与启动的领先幅度在低端机上会更明显。
- 功耗目前用 CPU 占用作代理(测试机的电量统计接口受限,无法直接读取放电功耗);真实功耗待换用无此限制的设备或外接功率计验证。
- 绝对时延/温度数值会随环境与设备热状态浮动;本页给出的是同 session、背靠背的相对对比。

## 7. 复现

```bash
export PATH=$PATH:$ANDROID_HOME/platform-tools
# Migo release AAR(出货配置):scripts/build-aar.sh release arm64-v8a(在 migo 仓库里)
bash scripts/run.sh --runtime webview --game bunnymark --device <SERIAL> --duration 60 --cold-runs 3
bash scripts/run.sh --runtime migo    --game bunnymark --device <SERIAL> --duration 60 --cold-runs 3 --migo-aar local:.../migo-release.aar
bash scripts/run.sh --runtime migo    --game bunnymark --device <SERIAL> --scenario stress --duration 55 --migo-aar local:...
python3 scripts/compare.py --results out/results.csv --game bunnymark --vs-webview

# 控温 stress A/B(冷却门到同温冷态 + 三 cluster 频率采样 + 各跑 2 次;见 §4):
bash scripts/stress-ab.sh <SERIAL> <path/to/migo-release.aar>
```

基线快照:`baselines/mate30.csv`。
