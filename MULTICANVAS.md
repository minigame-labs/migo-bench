# 多离屏 Canvas：这个仓库里最贵的内存形状

## 为什么加这两个游戏

`game-multicanvas-80` 和 `game-multicanvas-240`：N 个 128×64 的离屏 Canvas2D，每帧各重绘
一段短文本。这是商城 UI / 标签缓存的形状——**不是游戏**，而是引擎里单位内存最贵的用法。

已发布矩阵里的三个游戏没有一个是这个形状，所以「每个离屏 canvas 的固定成本」这项改动
在这套 harness 里此前完全不可见。

## 每个离屏 canvas 值多少钱

Mate 30 Pro（Kirin 990 / Mali-G76），`dumpsys meminfo` 的 Graphics 段，
migo 仓库的 `scripts/measure-skia-floor-pss.sh`：

| 配置 | Graphics | 每 canvas 边际 |
|---|---|---|
| 0 个离屏 canvas | 9.2 MB | — |
| 80 个，只建 EGL context + pbuffer | 24.9 MB | **0.20 MB** |
| 80 个，完整 2D 上下文 | 398.3 MB | **4.86 MB** |

中间那一行的 fixture 只调 `migo.createCanvas()`、不调 `getContext('2d')`：EGL context 和
pbuffer 会建，Skia 的 `GrDirectContext` 不会。两者之差就是拆分点——**96% 是 Skia context**，
不是像素（128×64 只有 32 KB）。

## 共享一个 Skia context 的收益与代价

两个 AAR 来自同一棵树、只差 `canvas_shared_direct_context` 的默认值，三轮交替：

| 80 canvas | off | on | |
|---|---|---|---|
| PSS | 650 [648–652] MB | **286 [286–287] MB** | −56% |
| 可玩耗时 | 1089 [1081–1094] ms | **452 [441–462] ms** | −59% |
| CPU | 125 [123–126] | 124 [124–124] | 平 |
| fps | 60 [60–60] | 54 [54–55] | **−9%** |

引擎侧默认**关闭**：这是取舍不是缺陷，该由宿主按自己的内容决定。

## ★ 60 fps 在这里会骗人

80 canvas 时未共享那臂恒定 60——那是 vsync 封顶。**55 对 60 只说明「偶尔漏了一帧」，
不是吞吐量的比值**，两个数在顶下根本不可比。240 canvas 的变体把两臂都压到顶以下：

| 240 canvas | off | on |
|---|---|---|
| PSS | 1.65 GB | 578 MB |
| fps | 25 | 23 |

这时 fps 才重新是比值。同 [JITLESS.md](JITLESS.md) 那次的教训：三个游戏在顶下全部打平，
掀开顶后同样的构建差 2.4–16×。**任何贴着 60 跑的对比，先确认自己没在读天花板。**

## 这些数不能被拿去说什么

- **不是 migo 对 WebView 的对比**，两臂都是 migo，差的是引擎的一个默认值。
- **是合成负载**：整齐排列的 N 个同尺寸 canvas 每帧全重绘，真实内容通常更少、更不规则。
  可移植的是**结构**（每 canvas 的固定成本由谁构成），不是绝对值。
