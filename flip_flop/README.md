# flip_flop：时钟边沿、异步复位与随机输入下的 D 触发器波形实验

一个用 Verilog 写的入门级 FPGA 小项目：**1 个上升沿 D 触发器 + 异步低电平复位**，配一个 50 MHz 时钟、两次复位、每 20 ns 随机翻转输入的 testbench，用 ModelSim 把"时钟上升沿 / 下降沿 / 复位 / 随机输入"四者与输出的关系在波形上一次性看清楚。

> 项目性质：学习用最小工程，**已完成 RTL 仿真验证（ModelSim），未做引脚约束，未上板验证**。所有结论都来自实测的 ModelSim 仿真日志（原始输出保留在第 5 节；日志文件由 ModelSim 运行时生成，仓库不提交）。

---

## 1. 项目解决了什么：用 ModelSim 讨论这个波形

初学者最容易含糊的四个问题，这个项目用一份可复现的波形回答：

| 问题 | 仿真给出的答案 | 日志证据（`msim_transcript`） |
| --- | --- | --- |
| 输出在时钟**上升沿**变化吗？ | 是，`led_out` 只在上升沿更新 | 日志中 `led_out` 的变化时刻全部是 20 ns 的整数倍（20、60、160、180、200…），这些正是上升沿 |
| 输出在时钟**下降沿**变化吗？ | 否，下降沿只是保持 | 下降沿在 10、30、50、230、250… ns，`led_out` 在这些时刻从未因时钟而改变 |
| 复位是同步还是异步？ | 异步低电平清零 | 220 ns 时 `led_out=1`；230 ns `sys_res_n` 拉低，同一时刻 `led_out` 立即变 0，不等上升沿 |
| 随机输入下输出怎么走？ | 上升沿采样的是**该沿之前**的 `key_in`，表现为滞后一拍（20 ns） | 160 ns `key_in` 变 0 → 180 ns 上升沿 `led_out` 才变 0；220 ns `key_in` 变 0 → 240 ns `led_out` 才变 0 |

关于"下降沿"这一点需要说明清楚：**RTL 里只有 `posedge sys_clk` 一个时钟敏感沿**，所以下降沿不产生任何动作，输出保持。如果你想要的是真正的双沿（上升沿和下降沿都更新，类似 DDR 触发器），现在这份代码是不做的——波形上看到的"下沿没反应"正是它的正确行为，而不是仿真出错。

**复现步骤**（Quartus 与 ModelSim 环境见第 3 节）：

```tcl
# 在 ModelSim 的 transcript 里执行
vlib work
vlog ../rtl/flip_flop.v ../sim/tb_flip_flop.v
vsim -voptargs=+acc work.tb_flip_flop
add wave *
run 1 us
```

跑完后在 Wave 窗口里加一条 `led_out` 的变化标记，会看到：**`led_out` 的所有跳变都落在上升沿，`sys_res_n` 拉低时立即掉到 0，两次复位之间 `led_out` 跟着 `key_in` 一拍一拍地走**。这就是这个项目要讨论的全部内容。

---

## 2. 主要功能

### 2.1 RTL：1 位上升沿 D 触发器（`rtl/flip_flop.v`）

```verilog
module flip_flop
(
    input wire sys_clk,   // 50MHz
    input wire sys_res_n, // 异步复位，低有效
    input wire key_in,

    output reg led_out
);

always @(posedge sys_clk or negedge sys_res_n)
    if (sys_res_n == 1'b0)
        led_out <= 1'b0;
    else
        led_out <= key_in;

endmodule
```

行为可以归纳为两行：

| 条件 | `led_out` |
| --- | --- |
| `sys_res_n == 0` | 立即为 0（异步清零，与时钟无关） |
| `sys_clk` 上升沿且 `sys_res_n == 1` | 取 `key_in` 的值 |
| 其他时刻（含 `sys_clk` 下降沿） | 保持不变 |

### 2.2 Testbench：50 MHz 时钟、两次复位、随机输入（`sim/tb_flip_flop.v`）

| 激励 | 实现 | 实际数值 |
| --- | --- | --- |
| 时钟 | `always #10 sys_clk = ~sys_clk;` | 周期 20 ns，即 50 MHz |
| 复位 | `sys_res_n` 初值 0，t=20 ns 释放；t=230 ns 再次拉低，t=270 ns 释放 | 两次复位，第二次持续 40 ns |
| 随机输入 | `always #20 key_in <= {$random} % 2;` | 每 20 ns 随机取 0/1，与时钟上升沿同刻更新 |
| 观测 | `$monitor("@time %t:key_in=%b led_out=%b", ...)` | 任一信号变化就打印一行 |

### 2.3 综合结果（Quartus Prime Lite 23.1std.1，Cyclone IV E EP4CE10F17C8）

| 项目 | 占用 |
| --- | --- |
| Total logic elements | 1 / 10,320（< 1 %） |
| Dedicated logic registers | 1 / 10,320（< 1 %） |
| Total pins | 4 / 180（2 %） |
| Memory bits / 乘法器 / PLL | 0 |

即：整个设计就是一个触发器，正好对应"一个 always 块、一个 `reg`"。

### 2.4 目录结构

```text
flip_flop/
├── README.md                        # 本文件
├── LICENSE                          # MIT 许可证
├── .gitignore                       # 排除编译/仿真产物
├── rtl/flip_flop.v                  # 设计源码（D 触发器）
├── sim/tb_flip_flop.v               # 测试激励（时钟/复位/随机输入/$monitor）
└── quartus_prj/                     # Quartus Prime 工程
    ├── flip_flop.qpf / flip_flop.qsf   # 工程与设置（器件、顶层、文件、仿真配置）
    └── （以下均为编译/仿真时自动生成，已被 .gitignore 排除，仓库内不含）
        ├── simulation/questa/          # Nativelink 生成的 .do 脚本、仿真库、msim_transcript 日志
        ├── output_files/               # 编译产物（.sof、.rpt、.pin…）
        ├── db/、incremental_db/         # 编译数据库
        └── modelsim.ini                # 仿真库映射
```

---

## 3. 安装方法

**需要的软件**

| 软件 | 本项目使用的版本 | 说明 |
| --- | --- | --- |
| Quartus Prime Lite | 23.1std.1 Build 993（工程由该版本创建） | 打开工程、编译、生成 Nativelink 仿真脚本；更老/更新的 Lite 版本通常也能打开 |
| ModelSim - Intel FPGA Edition | 10.5b（日志中的 Starter/Intel FPGA Edition） | 跑 RTL 仿真；Questa Intel FPGA 同样可用 |

**器件与语言设置**（已写在 `quartus_prj/flip_flop.qsf`）：Family = Cyclone IV E，Device = EP4CE10F17C8，顶层实体 = `flip_flop`，Verilog-2001，仿真工具 = Questa Intel FPGA (Verilog)，仿真时间刻度 1 ps。

**获取与准备**

```bash
git clone <本仓库地址>
cd flip_flop
```

只想跑仿真的话，**`rtl/` 和 `sim/` 两个文件就够了**，不需要 Quartus 编译产物；`quartus_prj/` 里除 `flip_flop.qpf`、`flip_flop.qsf` 外的 `db/`、`incremental_db/`、`output_files/`、`simulation/` 都是编译/仿真生成物，重新编译会整体覆盖，因此**没有放进仓库**（`.gitignore` 已排除），clone 后第一次编译或仿真时会自动重新生成。

注意：`quartus_prj/simulation/questa/flip_flop_run_msim_rtl_verilog.do` 由 Quartus 自动生成，里面写的是**生成机器上的绝对路径**（`E:/FPGA/flip_flop/...`）。换到别的目录或别的电脑时，请改用第 4 节的方法 B，或把该文件里的路径改成自己的。

---

## 4. 使用方法

### 方法 A：Quartus + Nativelink（一键跑 RTL 仿真）

1. 用 Quartus Prime 打开 `quartus_prj/flip_flop.qpf`。
2. 菜单 `Tools → Run Simulation Tool → RTL Simulation`。
3. Quartus 会调用 ModelSim 执行 `simulation/questa/flip_flop_run_msim_rtl_verilog.do`，脚本内容为：编译 `rtl/flip_flop.v` 与 `sim/tb_flip_flop.v` → `vsim tb_flip_flop` → `add wave *` → `run 1 us`。
4. 波形窗口出现后，重点看 `sys_clk`、`sys_res_n`、`key_in`、`led_out` 四条曲线（对应第 1 节的四个问题）。

### 方法 B：只用 ModelSim（不依赖 Quartus 工程路径）

在任意可写目录（例如 `flip_flop/sim/`）下执行，注意把路径改成自己的相对位置：

```tcl
vlib work
vlog ../rtl/flip_flop.v ./tb_flip_flop.v
vsim -voptargs=+acc work.tb_flip_flop
add wave *
run 1 us
```

只想看文本结果时，用控制台日志即可：tb 里的 `$monitor` 每次信号变化都会打印一行 `@time ...:key_in=.. led_out=..`。仿真结束后 ModelSim 会在 `simulation/questa/` 下生成 `msim_transcript` 文本日志，可以对着一行行读（该文件是生成物，不在仓库里）。

### 改激励

需要观察别的情形时，改 `sim/tb_flip_flop.v`：

- 复位时刻与宽度：`initial` 块里的 `#20`、`#210`、`#40`；
- 时钟频率：`always #10 sys_clk = ~sys_clk;`（改成 `#5` 就是 100 MHz）；
- 随机输入：`always #20 key_in <= {$random} % 2;`（`$random` 可用 `$random(seed)` 固定种子，使波形可复现）。

---

## 5. 输入输出示例

**输入**：50 MHz 时钟（20 ns 周期）、t=20 ns 释放第一次复位、t=230~270 ns 第二次复位、`key_in` 每 20 ns 随机翻转。

**输出**：`led_out` 的波形，以及 `$monitor` 打印的文本。下面这些行摘自本工程实测的仿真日志（ModelSim 运行后生成 `simulation/questa/msim_transcript`，仓库不提交该文件；时间单位 ps；除 t=0 那一行外，各次运行在相同时刻的值完全一致，t=0 的差异见本节末尾说明）：

```text
@time                    0:key_in=0 led_out=x
@time                20000:key_in=0 led_out=0
@time                40000:key_in=1 led_out=0
@time                60000:key_in=1 led_out=1
@time               160000:key_in=0 led_out=1
@time               180000:key_in=1 led_out=0
@time               200000:key_in=1 led_out=1
@time               220000:key_in=0 led_out=1
@time               230000:key_in=0 led_out=0
@time               240000:key_in=1 led_out=0
@time               280000:key_in=0 led_out=1
@time               300000:key_in=1 led_out=0
```

把上面这段整理成时序表（`clk` 在 20 ns 整数倍处为上升沿，在 10 ns 奇数倍处为下降沿）：

| 时刻 (ns) | clk | sys_res_n | key_in | led_out | 说明 |
| --- | --- | --- | --- | --- | --- |
| 200 | 上升沿 | 1 | 1 | 1 | 上升沿采样，`key_in` 前值为 1 |
| 210 | 下降沿 | 1 | 1 | 1 | 下降沿不动作，保持 |
| 220 | 上升沿 | 1 | 0 | 1 | `key_in` 与本沿同刻变 0，本沿仍采样旧值 1 |
| 230 | 下降沿 | 0 | 0 | 0 | 复位拉低，异步清零（不依赖时钟沿） |
| 240 | 上升沿 | 0 | 1 | 0 | 复位期间，上升沿也不能改变输出 |
| 250 | 下降沿 | 0 | 1 | 0 | 复位期间保持 0 |
| 260 | 上升沿 | 0 | 1 | 0 | 复位期间保持 0 |
| 270 | 下降沿 | 1 | 1 | 0 | 复位释放，但还没有上升沿 |
| 280 | 上升沿 | 1 | 0 | 1 | 复位后第一个上升沿，采样沿之前的 1 |
| 300 | 上升沿 | 1 | 1 | 0 | 采样沿之前的 0（`key_in` 与本沿同刻变 1） |

从这张表可以读出三件事：

1. **只有上升沿改变 `led_out`**（210、230、250、270 这些下降沿列里 `led_out` 都没有因为时钟而改变；230 的改变来自复位）。
2. **复位优先且异步**：230 ns 复位一到，`led_out` 立刻为 0，240/260 ns 的上升沿无法把它拉回 1。
3. **采样的是"沿之前"的值**：220、280、300 ns 三处，`key_in` 恰好在上升沿同一时刻翻转，触发器采到的是翻转前的旧值，因此 `led_out` 看起来总是比 `key_in` 慢一拍（20 ns）。原因是激励用了非阻塞赋值 `key_in <= ...`，其更新发生在时钟沿采样之后。

> 顺便说明日志第一行：t=0 时 `led_out` 可能是 `x`。因为 `sys_res_n` 在 `initial` 块里用非阻塞赋值从 `x` 变成 0，这次 `x→0` 跳变也算一次 `negedge`，会触发异步复位分支；`$monitor` 在 t=0 打印的是这次更新之前还是之后，取决于同一时刻的调度顺序，所以不同次运行会看到 `x` 或 `0`。

---

## 6. 已知限制与注意事项

写得直白一些，避免别人 clone 之后困惑：

- **没有 `.sdc` 时序约束**：Timing Analyzer 因此用默认的 1 ns 周期建立时钟（`create_clock -period 1.000 -name sys_clk`），并报 `Timing requirements not met`、slack −3.000 ns。这只是缺约束的产物，不代表 50 MHz 下有时序问题；要严谨就该补一个 20 ns 周期的 `create_clock`。
- **没有引脚约束**：编译会报 `No exact pin location assignment(s) for 4 pins of 4 total pins`（Critical Warning），4 个端口都未绑定到实际管脚，所以**编译出的 `.sof` 不能直接下载到板子上跑**——本项目定位是 RTL 仿真。
- **testbench 被加进了 Quartus 工程**（`.qsf` 里的 `VERILOG_FILE ../sim/tb_flip_flop.v`），这是 Nativelink 仿真流程需要的；对应地，Analysis & Synthesis 也会分析这个含 `$random`、`$monitor` 的文件（仅有 Info/Warning，不影响综合结果）。
- **testbench 第 28 行的 `$timeformat` 参数非法**：`$timeformat(19,0,"ns",6)` 的 `units_number=6` 超出允许范围，每次仿真都会报一条可抑制错误 `(vsim-PLI-3022) ... Units_number must be in the range 0 to -15 inclusive`。日志依然正常输出；把 6 改成 `-9`（纳秒）即可消除。
- **复位时刻恰好压在下降沿上**：`sys_res_n` 在 230 ns 拉低，而 230 ns 同时也是时钟下降沿。此时序表能说明"复位一到就清零"，但严格区分同步/异步复位时不够干净；若要把这件事讲透，把复位拉低改到 235 ns 再跑一次即可。
- **没有 `$finish`**：`run 1 us` 跑完后仿真会停在 1 us，需要手动停止；日志里超过 1 us 的部分是手动继续运行产生的。
- **仓库不含编译与仿真产物**：`db/`、`incremental_db/`、`output_files/`、`simulation/`、`modelsim.ini` 等都由 Quartus/ModelSim 在本机生成，含本机绝对路径与主机名，已通过 `.gitignore` 排除；clone 后第一次编译或仿真会自动重建。
- **未上板验证、未做时序收敛**：本项目的定位是 RTL 仿真实验，没有引脚约束与时钟约束，也没有板级验证记录。

---

## 许可证与致谢

- 本项目采用 **MIT 许可证**，全文见 [LICENSE](LICENSE)。
- `quartus_prj/flip_flop.qpf`、`flip_flop.qsf`、`modelsim.ini` 等文件由 Intel Quartus Prime / ModelSim 自动生成，文件头的版权声明属于 Intel，请遵循其许可条款；MIT 许可证覆盖的是本项目的 RTL、testbench 与文档。
- 本仓库的 RTL 与 testbench 为个人学习代码，欢迎提 Issue 讨论波形与时序问题。
