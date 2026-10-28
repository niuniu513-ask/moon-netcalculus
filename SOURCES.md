# 来源、选题边界与有限查重

检索日期：2026-10-28（Asia/Shanghai）。结论：**在下列有限范围内未发现相同的 MoonBit 确定性网络演算核心；存在模型术语与数学基础的部分重叠。** 这不是“任何项目都不重合”的承诺，也不是赛事立项结论。

## 检索方法和局限

- Mooncakes：请求 `https://mooncakes.io/api/v0/modules?limit=10000&offset=0`，返回 3,385 项；按模块名、描述和关键词拆分筛选。元数据筛选不能证明每个模块没有未描述的功能。
- GitHub：15 组网络演算仓库查询，覆盖 network calculus / 网络演算、min-plus / minplus、arrival curve、service curve、backlog bound、delay bound、leaky bucket、traffic envelope、deterministic network、tropical、netcalc。分别搜索描述和 README。
- GitHub 源码：arrival_curve、service_curve、min_plus、minplus、network_calculus、backlog+bound、deconvolution；无语言限制的 Network Calculus 查询用于识别其他语言成熟工具，不用于宣称原创。源码查询受 GitHub 默认分支、索引、分词及访问权限限制。
- 精确标识 `arrival_curve`/`service_curve`/`network_calculus`/`minplus` 在该次 MoonBit 代码检索均未返回命中。`min_plus` 命中 Azimuth 的整数测试变量 `min_plus_one`，已读取源码排除。deconvolution 命中 BioSeqs 的生物样本反卷积，不属于 min-plus 网络演算。
- backlog+bound 共 65 个源码结果（完整一页回读）；主要是 socket backlog、任务积压等宽泛词义，不凭这些结果为空来下结论。相邻项目按下表核查了实际 README、公开接口或实现文件；没有逐行审计全部 3,385 个模块。
- 初选贝叶斯图推断方向因 `tyytyy68/moon-bayes-kit` 的 README、源码树与 `graph_inference_production.mbt` 已包含相关能力而排除。这一结果说明标题检索不足以证明空白。
- 原始响应、检索 URL、失败请求和源码快照保存在本地项目外的研究资料目录；本文件保留可公开的结论。私有/未索引/未发布项目不在可验证范围。新项目可在检索后出现，提交前需刷新。

## 相邻生态逐项比较

| 项目与已核查证据 | 已有输入/输出与能力 | 本项目关系与需要验证的新增内容 |
| --- | --- | --- |
| [usersD609/moonqueuelab](https://github.com/usersD609/moonqueuelab)，README、pkg.generated.mbti、general_service.mbt、service_capacity 示例路径；树 SHA `1d6ae082c41b5a7a4ad4142bcee506e443444010` | 到达率、服务时间分布或路由 → 稳态均值/尾概率、Jackson/MVA、服务器整数配置；有完整容量规划 | 共同面向容量分析，不能声称容量规划生态为空。新核心是确定性到达/服务包络、最坏偏差、min-plus 与跨流剩余服务，不实现已有 Erlang/Jackson/MVA 算法；全时域/窗口/观测三类语义有独立验证 |
| [Ljh684/moonnet-lab](https://github.com/Ljh684/moonnet-lab)，README、src/net/link.mbt；树 SHA `1d08088611a834b4e323c051c76dbcbf1fa76e09` | 包、链路带宽、丢包和 TCP 策略 → 可重放逐包轨迹与统计 | 同样研究网络性能；本项目不复制仿真内核或 TCP，而分析满足包络的全部流量。独立物理计算用于验证模型界，不宣称仿真能证明未来界；未实现该库适配器 |
| [wcx789ll/moonsim](https://github.com/wcx789ll/moonsim)，README、network/pkg.generated.mbti；树 SHA `cf1d8a0573d8237d587a050618f4a589b1da6110` | 虚拟事件、资源、网络故障 → 轨迹、排队/SLA 统计 | 共享排队问题但方法与交付对象不同；这里交付模型包络代数及保守界，不重写事件循环。可交换普通时间/工作量记录，但没有宣称直接依赖或已集成 |
| [RunnerQuan/moonlimit](https://github.com/RunnerQuan/moonlimit)，README、pkg.generated.mbti、moonlimit.mbt；树 SHA `496cdc1b60e44012c2d2949017f30606767d038c` | 运行时时间、请求令牌 → allow/retry_after；含 TokenBucket/GCRA/多策略与模拟 | 令牌桶概念确实重叠。这里只将 `(burst,rate)` 作为到达契约并计算服务界/违例，未实现运行时 allow/retry_after 限流器；不是为了独立另写一份 MoonLimit |
| [vivid-oi/MoonQuotaKit](https://github.com/vivid-oi/MoonQuotaKit)，README、源码树；树 SHA `46dd87717463a7b16b587cde8d5a30c94d050ef9` | 配额、层级、批请求 → 原子多维计费与公平调度 | 相邻准入概念；本项目的 admit 只判断曲线预算，不持有/扣减令牌、不实现公平队列。该 API 是解析核心的预算判定，不宣称新的运行时调度核心 |
| [moonbitstack/moonward](https://github.com/moonbitstack/moonward)，README、源码树；树 SHA `483060e8ee908662fe62ac3bd9936ec3c2755652` | 时间/调用状态 → 熔断、限流、负载丢弃、重试 | 不提供本项目的到达—服务曲线分析；本项目不复制这些运行时机制 |
| [trail-it/moonpressure](https://github.com/trail-it/moonpressure)，README | cgroup 采样、共享祖先和作业申请 → 资源准入/预留生命周期 | 同有预算判断，但其核心是操作系统资源关系及预留；本项目是无 I/O 的流量服务模型，无 cgroup 或作业预留 |
| [wcj12314/MoonFlowGuard](https://github.com/wcj12314/1231)，README | CSV/网络流记录 → 安全规则、风险、策略门禁 | 观测审计术语相邻；本项目不做安全风险分类，而做时间—工作量区间的数学包络核验 |

上述资料是在检索日读取的远端默认分支状态，树 SHA 是 Git tree 标识，不冒充提交 SHA。未核查其全部分支、未发布版本、维护者计划或官方审核意见；不凭 README 中的能力缺省认定永久没有该功能。独立模块的必要性在于不同的到达/严格服务模型、偏差代数与交叉流量证明责任；最终生态新增价值由评审判断。

## 数学来源和其他语言同类

- Jean-Yves Le Boudec / Patrick Thiran, [Network Calculus](https://leboudec.github.io/netcal/)，LNCS 2050。参考其公开到达/服务曲线、串联、剩余服务与偏差定义；没有复制书籍正文、插图或源文件，免费可读不等于其内容可任意再分发。
- [NetCal/DNC](https://github.com/NetCal/DNC) 是成熟的 Java 确定性网络演算工具，功能大于本项目。它证明该领域是既有方法，本项目不是全球首次提出，也不是它的完整 MoonBit 移植。仅查阅项目定位和能力介绍，没有复制、翻译或链接其源代码；其许可证不作为本项目的许可证。
- [MoonBit core](https://github.com/moonbitlang/core)，Apache-2.0，通过官方工具链链接使用；不内嵌 core 源码。CLI 的按后端处理进程参数使用 core/env 的公开语义；不把它作为新的算法贡献。

## 原创与合规范围

本项目在公开数学定义上独立编写 MoonBit 实现、测试、合成样例和验证脚本。算法知识有来源，源码独立不等于功能独占。唯一编译依赖为官方 core，没有伪造上游扩展或维护者认可；与邻近包尚无直接适配集成。

根目录 MIT 适用于本项目源码。数据由本项目构造，验证随机种子固定；没有真实个人或客户数据。`pkg.generated.mbti` 由 `moon info` 生成。研究快照、报名材料及私人评审记录不属于公开源码或发布包。
