# Canvas2D 精灵路径：一条此前没有被任何 bench 覆盖的路

## 为什么要加这个游戏

这个仓库的三个 bench 游戏，资产目录里**一张图片都没有**：

```
$ find shells/migo-shell/app/src/main/assets/game{,-canvasmark,-endless-runner} -type f
.../game/game.js          .../game/game.json
.../game-canvasmark/game.js   .../game-canvasmark/game.json
.../game-endless-runner/game.js   .../game-endless-runner/game.json
```

bunnymark 走 Pixi 的 WebGL 路径，endless-runner 走 Phaser 的，而本仓库这个 canvasmark
变体里 `drawImage` 出现 **0 次**。也就是说，**引擎的 Canvas2D 图像路径——一个 2D 回退
渲染器和一个手写小游戏真正会走的那条——在这里一直是没有量过的**。

代价是具体的：2026-09-01 有一轮针对该路径的优化，跑完整个矩阵后每一项都落在噪声里，
差点被记成「改动无效」。真正的原因是**这个矩阵根本没有触到被改的代码**。

## 这个游戏是什么

`shells/migo-shell/app/src/main/assets/game-sprite-batch/`：一个 30×50 的确定性点阵，
每帧 1500 次 `ctx.drawImage`，混合四种形状，因为一个精灵批处理器必须把它们区分开：

* 同一张图 1:1 的长连续段
* 同一张图**均匀放大**的段（旋转-缩放变换能表达）
* 每 8 行**换一张图**
* 每 37 个一个**非均匀缩放**的精灵（`RSXform` 无法表达两个不同的缩放，
  必须让它把连续段断开，而**不移动**它的邻居）

没有时钟、没有随机数进入绘制，所以两次运行只应该差在运行时上。一个忽略自己
准入规则的批处理器，表现出来的是**像素位移**，而不只是一个不同的数字。

图源是两张真 PNG，不是 canvas：`drawImage` 会**静默丢弃**未加载的源，而这个 fixture
的第一版正是用 `migo.createCanvas()` 当图源，结果画面只有背景色，日志却照报
"768 sprites"。加载完成前不绘制，也是这个原因。

## 测出来的数

Mate 30 Pro（Kirin 990 / Mali-G76），`scripts/ab-run.sh`，两个 AAR 来自同一棵树、
三轮交替、每格独立过温度门。协议见 [MEASURING.md](MEASURING.md)。

| | v0.9.6 | 精灵批之后 | |
|---|---|---|---|
| CPU | **96 %** [96–107] | **82 %** [78–85] | **−14.6 %** |
| PSS | 101598 KB | 101861 KB | +0.3 % |
| fps | 60 | 60 | — |
| first frame | 226 ms | 223 ms | — |
| game ready | 324 ms | 328 ms | — |

**两臂的 CPU 区间完全不重叠**（96–107 vs 78–85），远在 MEASURING.md §5 记录的
1–2 % CPU 噪声地板之外。fps 两边都钉在 60，因为这个负载还没顶到 vsync 上限——
CPU 才是这里的仪器（同 [JITLESS.md](JITLESS.md) 的教训）。

改动本身是两半：帧收集器把**相邻的 `drawImage` 折叠**成一条批命令，渲染侧再把批里
**同图、同均匀缩放的连续段**交给一次 `SkCanvas::drawAtlas`。折叠的正确性只依赖一件事：
两条相邻的 `drawImage` 之间不可能夹着状态命令，因为状态变更本身也是命令。

## 这个数不能被拿去说什么

* **它不是 migo 对 WebView 的对比。** 两臂都是 migo，差的只是引擎版本。
  发布矩阵在 [RESULTS.md](RESULTS.md)。
* **它不覆盖压缩纹理。** 这个 fixture 的 PNG 很小，KTX2/mip 那条路没有被它触到。
* **它是一个合成负载。** 1500 个精灵的规整点阵不是任何一个真实游戏；它是为了让
  per-sprite 的成本盖过其它一切而设计的，好让这条路径上的改动能被看见。
