# 把热点 crate 的 codegen 等级调高，值不值那 1.29 MiB

发货的 Android `libmigo.so` 整棵树按 `opt-level = "z"` 编译。引擎仓库里备着两个
选择性 profile（`release-hot2` / `release-hot3`），把五个"热点"工作区 crate
——`migo-audio`、`migo-core`、`migo-graphics`、`migo-io`、`migo-runtime-v8`——
分别提到 `opt-level = 2` 和 `3`，其余依赖仍留在 `z`。

这两个 profile 建起来是为了回答一个问题，而不是为了发货。问题一直没有答案，
profile 就一直躺在树里，还配着一个门禁（`test-q14-codegen-profiles.sh`）保证
它们不被改坏。**2026-08-25 在真机上把 hot2 那一半量掉了。**

## 结论

hot2 在十二个格子（三游戏 × 首帧/可玩/CPU/PSS）里**没有一格给出可分辨的收益**，
而它让发货 `.so` 涨 1,294,336 字节（+3.2%），`.text` 涨 1,507,336 字节（+5.2%）。

而且它**过不了体积门禁**：`.text` 30,744,432 字节，预算 30,700,000，超 44,432。

```
$ scripts/test-android-so-size-contract.sh migo-full-release-opt2-arm64-v8a.aar
FAIL: ... libmigo.so is over budget.
  .text     30744432 bytes, budget 30700000 (over by 44432)
      Code size. ... that the codegen profile is still 'z'.
```

门禁的提示词把原因直接点名了。这不是巧合——那条提示是上一次 `.text` 失控时写的。

## 三游戏 × 两配置

Mate 30 Pro（TAS-AN00, Android 12 / SDK 31），三轮交错，臂序逐轮交替，
`ab-run.sh --label-a optz --label-b opt2`。噪声地板取 `MEASURING.md` §4b。

| 游戏 | 指标 | z（当前发货） | hot2 | 差 | 噪声地板 | 判定 |
|---|---|---|---|---|---|---|
| bunnymark | 首帧 | 226 ms | 228 ms | +1.3 ms | 14 ms | 噪声内 |
| bunnymark | 可玩 | 392 ms | 386 ms | −6.3 ms | 20 ms | 噪声内 |
| bunnymark | CPU | 43% | 43% | ±0 | 1 pt | 噪声内 |
| bunnymark | PSS | 110 MB | 110 MB | +0.2% | 1% | 噪声内 |
| canvasmark | 首帧 | 230 ms | 227 ms | −2.3 ms | 14 ms | 噪声内 |
| canvasmark | 可玩 | 324 ms | 320 ms | −3.7 ms | 20 ms | 噪声内 |
| canvasmark | CPU | 73% | 72% | −1.3 pt | 1 pt | 见下 |
| canvasmark | PSS | 87 MB | 87 MB | +0.6% | 1% | 噪声内 |
| endless-runner | 首帧 | 321 ms | 309 ms | −11.3 ms | 14 ms | 噪声内 |
| endless-runner | 可玩 | 653 ms | 684 ms | +30.7 ms | 20 ms | 见下 |
| endless-runner | CPU | 41% | 41% | −0.7 pt | 1 pt | 噪声内 |
| endless-runner | PSS | 202 MB | 203 MB | +0.1% | 1% | 噪声内 |

原始行：`out/jitless_ab.csv`（`arm` 列为 `optz` / `opt2` 的 18 行）。

## 那两格越过地板的，看配对差就散了

§4b 说过「不重叠的区间在 n=3 上不构成证据」。这次两格正好演示了它，而且方向相反
——一格对 hot2 有利、一格不利，两格都由单独一轮独扛：

```
canvasmark     CPU    z=[72, 70, 78]    hot2=[72, 74, 70]    配对差=[0, +4, −8]
endless-runner 可玩   z=[592, 638, 729] hot2=[700, 631, 720] 配对差=[+108, −7, −9]
```

canvasmark 的 CPU 在同一条臂内自己就摊开 8 个点（`[72, 70, 78]`），而 §4b 的
1 点地板是在 endless-runner 上标定的——**地板不跨游戏搬**。endless 的可玩更直白：
第一轮 +108 ms 把均值整个抬起来，第二三轮是 −7 和 −9。

如果只看均值和"不重叠"，这两格会分别被写成「hot2 省 1.3 点 CPU」和
「hot2 慢 31 ms」。两句都是假的。

## 这一次的温度门没守住，说明白

18 次里有 17 次打了 `PROCEEDED-UNGATED`：白天环境温度上来了，机身稳态落在
36,000–37,000 mC，而门限是 35,000 mC，等满 420 s 也降不下去。装置如实报了
WARNING 并继续。

对**这次比较**不致命：两条臂同处一个 session、同样受热、臂序逐轮交替——交错设计
要防的就是这个。但这些行的**绝对值**不能拿去和任何一个过了温度门的 session 比，
§3 那条照常成立。

## hot3 没量

只测了 hot2。hot3 没有数据，本文不替它下结论。可以说的是机械事实：
`opt-level = 3` 生成的代码不会比 `2` 小，而 hot2 已经超了 `.text` 预算 44 KB。
真要量，就按下面重跑一遍，别从这张表推。

## 复现

```sh
# 两个 AAR 只能差一个 profile，其余（V8 归档、快照、链接 flag）必须同源
cd ../migo
bash scripts/build-aar.sh --output-dir dist-ab-z arm64-v8a   # z 臂（发货配置）
bash scripts/build-aar.sh --codegen-profile 2 --output-dir dist-ab-2 arm64-v8a

cd ../migo-bench
bash scripts/ab-run.sh --device <SERIAL> \
  --jit-aar     ../migo/platforms/android/dist/migo-full-release-arm64-v8a.aar \
  --jitless-aar ../migo/platforms/android/dist-ab-2/migo-full-release-opt2-arm64-v8a.aar \
  --label-a optz --label-b opt2 --rounds 3
```

（`--jit-aar` / `--jitless-aar` 是装置出生时的名字，读作臂 A / 臂 B。）

体积那一半不需要设备：

```sh
cd ../migo
scripts/test-android-so-size-contract.sh <每个 AAR>
```

## 更新记录

- **2026-08-25** 首次测量。hot2：十二格全在噪声内，代价 +1.29 MiB，且超 `.text`
  预算 44 KB。发货配置维持 `z`。hot3 未测。
