# migo-bench 对比结果

> 中文为默认版本；英文见 [RESULTS.en.md](RESULTS.en.md)。
> 原始数据:`out/results.csv`(稳态)、`out/stress_*.csv`(压力曲线)。每行都带完整溯源(Migo 版本、设备、WebView 版本、时间戳、`fps_source`)。

## 1. 结论先行

同一游戏、同一设备、同一交互,在 **Migo 原生运行时** 与 **Android 系统 WebView** 上对比。定位:Migo = 开源原生的 WebView 替代。**头条是一致性 + 可审计 + 内存/CPU 效率;帧率通常打平,从不夸大。**

- ✅ **内存:Migo 明显更省**(本轮 ~148MB vs WebView ~221MB,少约 33%)——关键:WebView 的渲染跑在**独立的 chromium 进程**里,必须把它算进去才公平(否则少算 ~100MB)。
- ✅ **CPU:Migo 约为 WebView 的一半**(48% vs 108%,同样 100 精灵 60fps)——原生 GL 比 Chromium 合成器更省 CPU;这也是功耗的代理指标。
- ≈ **游戏就绪(首帧可玩):基本持平**(Migo 525ms vs WebView 537ms)。
- = **帧率:打平**(都 ~60fps;压测到 20000 精灵仍都 60fps)。

> 注意:这是**高端机**(麒麟 990)。GTM 楔子市场是**低端机**,内存/启动差距会更大——低端机是下一步的核心测试(见矩阵)。

## 2. 测试矩阵(设备 × 游戏)

| 设备档位 \ 游戏 | bunnymark (Pixi v8) | endless-runner (Phaser) | Canvas2D(待选) |
|---|---|---|---|
| **高端** · 华为 Mate30 Pro(麒麟990/8G/A12) | ✅ 已测 | 🔜 计划 | 🔜 计划 |
| **中端**(~4G,待采购) | 🔜 | 🔜 | 🔜 |
| **低端** ⭐(~2-3G,待采购,GTM 楔子) | 🔜 | 🔜 | 🔜 |

> 目前 1 台设备 × 1 游戏已跑通;矩阵随设备到位逐格填充。每格产出下面这套指标。

## 3. 结果:Mate30 Pro × bunnymark(100 精灵,60s 稳态)

### 3.1 内存 🏆 Migo

| 指标 | WebView | Migo | 差异 |
|---|---|---|---|
| PSS 峰值 | **~221 MB** | **~148 MB** | **Migo 少 ~33%** |

- **公平口径**:WebView = 主进程 + chromium 沙箱渲染进程之和(`dumpsys meminfo <pkg>` 只算主进程,会漏掉渲染进程约 100MB)。Migo 是**单进程**,全部计入。
- PSS 有 ±几十 MB 抖动(GC/系统状态);多轮平均会更稳,方向(Migo 明显更省)稳健。

### 3.2 启动 ≈ 持平

| 指标 | WebView | Migo | 说明 |
|---|---|---|---|
| 首帧(系统 `Displayed`,ms) | 396 | 458 | 窗口首次绘制;Migo 多一层 Launcher→Game 跳转 + SurfaceView,不完全可比 |
| **游戏就绪(系统 `Fully drawn`,ms)** | **537** | **525** | **公平口径**:游戏首个真实帧 → `reportFullyDrawn()`。基本持平,Migo 略快(V8 快照抵消原生初始化) |

> "首帧(Displayed)"对 WebView 是空白窗口先绘制,偏早、两侧口径不一;**以"游戏就绪"为准**。

### 3.3 帧率 = 打平

| 指标 | WebView | Migo |
|---|---|---|
| fps 中位 | 60 | 59 |
| 1% low | 60 | 57 |

**压力曲线(游戏内确定性 ramp,`--scenario stress`)**:

| 精灵数 | WebView fps | Migo fps |
|---:|---:|---:|
| 100 | 60 | 59 |
| 1000 | 60 | 59 |
| 5000 | 60 | 60 |
| 12000 | 60 | 59 |
| 20000 | 60 | 60 |

两侧都撑到 20000 精灵仍 60fps——高端机的性能天花板都远在 20k 之上,吞吐打平。低端机或更高 ramp 才会分化。

### 3.4 CPU 🏆 Migo

| 指标 | WebView | Migo | 差异 |
|---|---|---|---|
| CPU 占用(多核,可 >100%) | **108%** | **48%** | **Migo ~一半** |

- 口径:`/proc/<pid>/stat` 的 (utime+stime) 增量;WebView 计入主进程 + chromium 渲染进程(与内存同理)。
- 同帧率下 Migo CPU 约为一半 → 更省电(见功耗)。单次采样,多轮会更稳。

### 3.5 功耗(代理)

真机功耗直接测量在本机受限:该 EMUI 设备**关闭了 fuel gauge**(`current_now` 不可读)且 **per-uid batterystats 能量模型不可用**,加上 USB 供电会掩盖电池放电。**当前以 CPU 占用作为功耗代理**(定帧率下 CPU 是主要功耗驱动)→ Migo 更省。
真·功耗待:①非华为设备(开放 fuel gauge)②断电跑 + 电量差 ③外接功率计。

## 4. 测量方法(系统级、app 无关、可审计)

- **内存**:`dumpsys meminfo`,WebView 求和主进程 + `:sandboxed_process`(`webview_pss.py`)。
- **启动**:系统 `am` 的 `Displayed`(首帧)+ `reportFullyDrawn`/`Fully drawn`(游戏就绪);不解析 app 日志。
- **帧率**:优先 `dumpsys SurfaceFlinger --latency`(合成器真实呈现时间戳,app 无关);**本设备 EMUI 屏蔽了该接口(全 0)**,回退到游戏自身 fps 遥测(两侧同源、对称),每行记 `fps_source`。非华为机会用 SurfaceFlinger。
- **CPU**:`/proc/<pid>/stat` 增量(WebView 含渲染进程)。
- **压力**:游戏内确定性精灵 ramp(Pixi ticker,两侧一致;`make-stress-game.sh` 生成),fps 对精灵数作曲线。
- **稳定性护栏**:采集前强制亮屏保持(`svc power stayon`)——熄屏会导致 activity 停止、零帧零数据。

## 5. 复现

```bash
export PATH=$PATH:$ANDROID_HOME/platform-tools
# 稳态:
bash scripts/run.sh --runtime webview --game bunnymark --device <SERIAL> --duration 60 --cold-runs 3
bash scripts/run.sh --runtime migo    --game bunnymark --device <SERIAL> --duration 60 --cold-runs 3 --migo-aar local:.../migo-debug.aar
# 压力曲线:
bash scripts/run.sh --runtime migo    --game bunnymark --device <SERIAL> --scenario stress --duration 48 --migo-aar local:...
```

Migo 版本可 pin:`--migo-aar local:PATH | release-tag:TAG | sha:SHA`——每个结果都钉在一个确切的 Migo 版本上(可审计)。
