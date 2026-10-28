# moon-netcalculus

MoonBit 确定性网络演算库。把**突发量与长期速率、节点服务能力、共享路径**转成可复查的缓存和延迟上界；从观测记录定位契约违例，再反解满足预算的服务容量。

核心代码由 MoonBit 实现，只依赖 `moonbitlang/core`。这是基于公开数学定义的独立实现，不宣称发明网络演算，也不宣称全网没有同类工具。与 MoonBit 相邻项目的关系和有限查重结论见 [SOURCES.md](SOURCES.md)。

## 三个不同的完整工作流

| 使用者与问题 | 输入 → 分析 → 输出 | 可运行程序 |
| --- | --- | --- |
| 平台设计者：服务链需要多少容量和缓冲区 | 流量突发/速率、各节点速率/时延、预算 → 服务串联、最坏界、容量反解 → 可行配置或明确不可行原因 | `examples/capacity` |
| 监控/数据管道开发者：实际流量是否满足声明的契约 | 有序时间与工作量记录、流量契约 → 所有事件区间核验、最坏反例、固定速率下最小观测突发 → 违例记录与只对观测成立的包络 | `examples/trace_contract` |
| 网络/实时系统工具作者：共享链路会怎样影响目标流 | 有向节点、严格服务曲线、各流路径 → 拓扑检查、交叉流量聚合、剩余服务、逐跳传播 → 各跳及端到端上界 | `examples/feed_forward` |

这些程序使用合成数据，不包含客户数据或实测设备性能。

## 已实现能力

- 令牌桶到达包络与速率—时延服务曲线；全时域 backlog、虚延迟、输出突发和利用率。
- 到达聚合、服务串联、任意复用下的剩余严格服务；速率相等和零流量边界明确处理。
- 延迟/缓存预算判定，以及满足目标的最小单节点服务速率；超载、不可行和数值溢出分别报错。
- 有限离散曲线的 min-plus 卷积、窗口反卷积、次可加闭包、和/最小/最大、垂直及水平偏差。
- 流量契约的完整事件区间检查、同时刻合并突发的反例、固定速率下最小观测突发、多个窗口的经验包络。
- 多流前馈网络分析；未知节点、重复 ID、重入和循环路由拒绝；同节点使用一致输入快照。
- 七类 JSON 请求、未知/重复字段拒绝、大小与计算规模限制；相同 CLI 在四个后端实际运行。

## 环境与运行

需要 MoonBit CLI。开发时验证过 `moonc v0.10.14+7d59c7ec9`、`v0.10.16+b1a0e846e`，最终使用官方 stable `v0.10.17+d971670cd`（`moon 0.1.20261023`）。JS 后端需要 Node.js，native 后端需要系统 C 编译器。Python 3.9+ 仅用于独立验证，不参与库或 CLI 的计算。

在项目根目录执行：

```sh
moon version --all
moon check --deny-warn --target all
moon build --target all
moon test --deny-warn --target all
moon run examples/capacity --target wasm-gc
moon run examples/trace_contract --target wasm-gc
moon run examples/feed_forward --target wasm-gc
```

容量示例第一行输出 `backlog=126`、`delay=18`；反解得到最小容量 `12`，将延迟上界降至 `13`。流量示例先报告违例，拟合突发量 `6` 后通过**观测记录**的复查。

依赖本地源码：将本目录作为工作区模块，在另一个包的 `moon.pkg` 中导入：

```moonbit
import {
  "niuniu513-ask/moon-netcalculus" @nc,
}
```

```moonbit
fn main raise {
  let a = @nc.token_bucket(10.0, 2.0)
  let s = @nc.rate_latency(5.0, 3.0)
  let report = @nc.bounds(a, s)
  println(report.delay) // 5
}
```

模块当前仅本地开发，尚未发布 Mooncakes。不要用尚不存在的 `moon add` 版本安装；独立消费者复现使用下面的本地复制验证命令。生成的 [pkg.generated.mbti](pkg.generated.mbti) 列出完整公开接口。

## JSON 命令行

PowerShell、bash 均可用单引号把一条 JSON 请求作为一个参数传入：

```sh
moon run cmd/main --target js -- '{"op":"bound","arrival":{"burst":10,"rate":2},"service":{"capacity":5,"latency":3}}'
```

```json
{"ok":true,"result":{"backlog":16,"delay":5,"output":{"burst":16,"rate":2},"utilization":0.4}}
```

`--target` 可选 `wasm`、`wasm-gc`、`js`、`native`。CLI 输出单行 JSON；业务失败通过 `ok:false` 和 `code` 表达，进程退出码不代表业务成功。可运行的请求文件在 `examples/requests/`，完整协议见 [docs/protocol.md](docs/protocol.md)。

## 验证与复现

```sh
moon fmt --check
moon info
python scripts/verify.py
python scripts/verify_consumer.py
```

第一份脚本对四个后端分别进行逐步流体服务器计算、曲线分解穷举、事件区间穷举和协议/拓扑错误检查。第二份脚本把必要源码复制到 `_build/consumer/`，生成一个独立包，通过公共接口运行；不访问远程或发布任何内容。CI 配置执行检查、构建、测试、示例和上述复现；配置存在不表示线上运行成功。

## 数学与工程边界

- 单位由调用者保持一致，例如 kB 与 ms；`rate` 和 `capacity` 都应为 kB/ms。输入没有隐式单位转换。
- 全时域解析界依赖**有效到达包络与服务曲线**。剩余服务要求节点提供严格服务曲线，逐包延迟解释要求流内 FIFO。它们是模型条件，不是从少量观测自动证明的事实。
- 当前是流体模型，不计包长、调度实现、协议开销、丢包、反馈控制或循环网络。不能把输出当成真实设备的无条件时延保证。
- `Curve` 表示 `0..H` 整数网格；离散卷积不是任意连续曲线的精确卷积。窗口结果带 `finite_window_only`。服务窗口不足时 `delay_upper_ticks` 为 `null`，不会填入虚假的有限上界。
- 反卷积只在已知窗口内取上确界，可能非单调；它返回 `WindowDeconvolution`，不能直接当作未来输出包络。解析 `bounds(...).output` 才是在相应模型假设下的全时域包络。
- `check_contract`/`fit_burst`/`empirical_envelope` 只说明观测记录，空记录是空观察，不证明未来符合。默认绝对容差为 `1e-9`，可以显式设为零。
- 使用 IEEE-754 Double，并检查非有限输入/中间结果；没有有理数或向外舍入证明。近边界规划应保留工程余量，不应把浮点输出称为形式化数值证书。
- 规模上限：曲线 512 ticks、记录 512 条、窗口 128 个、网络 64 节点/64 流、路径 64 跳、聚合/串联 128 项；JSON 上限 1,048,576 个 UTF-16 code units、深度 32。受操作系统参数长度限制，CLI 可传入的实际请求可能更短，嵌入式 `process_json` 不受命令行长度限制。

推导与算法复杂度见 [docs/mathematics.md](docs/mathematics.md)。MIT 许可证见 [LICENSE](LICENSE)，来源和非移植关系见 [SOURCES.md](SOURCES.md)。
