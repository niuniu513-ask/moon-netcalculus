# JSON 协议

调用 `process_json(String)` 或把完整 JSON 作为 CLI 的唯一参数。

成功输出 `{"ok":true,"result":...}`。失败输出 `{"ok":false,"code":"invalid|unbounded|infeasible|limit|numerical","message":"..."}`。使用错误另有 `usage`。业务错误仍输出合法 JSON，当前 CLI 不用非零退出码编码业务失败。

对象未知键、重复键（包含转义后相同的键）、缺字段、类型错误均拒绝。所有模型数字须有限且满足其非负/正约束。不接受字符串数字。`burst` 为工作量，`rate`/`capacity` 为工作量每时间，`latency` 为时间。字段和 ID 区分大小写。

## 解析请求

```json
{"op":"bound","arrival":{"burst":10,"rate":2},"service":{"capacity":5,"latency":3}}
```

可同时加入 `delay_limit` 与 `buffer_limit`；此时返回 `Admission`，包括 `admitted`、两个预算判断和 `metrics`。只加入其中一个拒绝。

```json
{"op":"tandem","arrival":{"burst":12,"rate":2},"services":[{"capacity":8,"latency":1},{"capacity":4,"latency":2}]}
```

返回串联服务和 `metrics`。

```json
{"op":"leftover","service":{"capacity":10,"latency":2},"cross":{"burst":6,"rate":2},"arrival":{"burst":4,"rate":1}}
```

`arrival` 可省略；省略时只返回剩余服务，否则同时返回该目标流指标。剩余服务的严格服务器假设必须由调用者保证。

```json
{"op":"capacity","arrival":{"burst":12,"rate":2},"latency":1,"delay_limit":3,"buffer_limit":14}
```

返回最小容量与必要缓冲区；不可行不输出猜测配置。

## 有限曲线请求

```json
{"op":"curve","operation":"convolve","a":[0,5,8,9],"b":[0,0,3,7]}
```

`operation` 为 `convolve`、`sum`、`min`、`max` 时返回数组；`deconvolve` 返回窗口值/最大化位移；`bounds` 返回有限窗口偏差。`closure` 只需要 `a`，传入 `b` 拒绝。其他操作要求两个曲线共享长度。曲线元素零点为零且非负非递减，最大 513 个采样。

窗口 `bounds` 返回 `backlog`、`backlog_tick`、`resolved_delay_max_ticks`、可空 `delay_upper_ticks`、`censored_samples`、`horizon`、`scope`。时间单位是 ticks，没有外推；有限窗口的上下界含义见数学说明。

## 观测请求

```json
{"op":"trace","events":[{"at":0,"amount":3},{"at":1,"amount":5},{"at":3,"amount":2}],"contract":{"burst":5,"rate":2},"fit_rate":2,"windows":[0,1,3],"tolerance":0}
```

`fit_rate` 默认等于 contract.rate；`windows` 默认 `[0,1,10]`；`tolerance` 默认 `1e-9`。返回 `contract`（符合/违反区间数/最坏见证）、`fit` 和 `empirical_envelope`。可选见证不存在时字段可能省略。事件为有序增量，可同时发生；不会静默排序。该结果仅对观测记录成立。

## 前馈网络请求

```json
{"op":"network","servers":[{"id":"edge","service":{"capacity":10,"latency":1}},{"id":"core","service":{"capacity":8,"latency":2}}],"flows":[{"id":"f","arrival":{"burst":4,"rate":1},"route":["edge","core"]},{"id":"x","arrival":{"burst":6,"rate":2},"route":["edge"]}]}
```

返回处理顺序、每流逐跳输入/交叉流量/剩余服务/指标、端到端指标、逐跳延迟和、最大单跳 backlog、出口包络以及假设。任一流当前模型不能有界时整个请求返回 `unbounded`；没有删除失败流后继续分析。未知路由、重入与联合环路返回 `invalid`。
