# VMAC 模块化重构设计

## 当前状态
- `vmac_unit.v`：437 行，包含所有功能
- 难以维护和展示

## 重构后的模块结构

### 1. vmac_regfile.v（配置寄存器模块）
**职责**：管理所有配置寄存器的读写
**接口**：
```verilog
module vmac_regfile (
    input wire clk,
    input wire resetn,
    
    // CPU 访问接口
    input wire [31:0] addr,
    input wire [31:0] wdata,
    input wire [3:0] wstrb,
    output reg [31:0] rdata,
    
    // 配置输出
    output reg [31:0] cfg_a_base,
    output reg [31:0] cfg_b_base,
    output reg [31:0] cfg_c_base,
    output reg [31:0] cfg_m,
    output reg [31:0] cfg_n,
    output reg [31:0] cfg_k,
    output reg [31:0] cfg_batch,
    output reg [31:0] cfg_a_stride,
    output reg [31:0] cfg_b_stride,
    output reg [31:0] cfg_c_stride,
    output reg [31:0] ctrl_reg,
    
    // 状态输入
    input wire busy,
    input wire done,
    input wire dma_active,
    input wire dma_error
);
```

### 2. vmac_dma_controller.v（DMA 控制器）⭐
**职责**：DMA 状态机、地址生成、错误处理
**接口**：
```verilog
module vmac_dma_controller (
    input wire clk,
    input wire resetn,
    
    // 配置输入
    input wire [31:0] cfg_a_base,
    input wire [31:0] cfg_b_base,
    input wire [31:0] cfg_c_base,
    input wire [31:0] effective_m,
    input wire [31:0] effective_n,
    input wire [31:0] effective_k,
    input wire [31:0] effective_batch,
    input wire [31:0] effective_a_stride,
    input wire [31:0] effective_b_stride,
    input wire [31:0] effective_c_stride,
    
    // 控制信号
    input wire start,
    output reg done,
    output reg error,
    
    // DMA 总线接口
    output reg dma_valid,
    output reg dma_we,
    output reg [31:0] dma_addr,
    output reg [31:0] dma_wdata,
    output reg [3:0] dma_wstrb,
    input wire dma_ready,
    input wire [31:0] dma_rdata,
    
    // 与计算核心的接口
    output reg [31:0] compute_wr_addr,
    output reg [31:0] compute_wr_data,
    output reg compute_wr_en,
    output reg compute_start,
    input wire compute_done
);
```

### 3. vmac_compute_core.v（矩阵计算核心）
**职责**：执行矩阵乘法运算
**接口**：
```verilog
module vmac_compute_core (
    input wire clk,
    input wire resetn,
    
    // 矩阵数据写入接口
    input wire [31:0] wr_addr,
    input wire [31:0] wr_data,
    input wire wr_en,
    
    // 控制信号
    input wire start,
    output reg done,
    
    // 配置
    input wire [31:0] m,
    input wire [31:0] n,
    input wire [31:0] k,
    
    // 结果输出
    output reg [31:0] result_c00,
    
    // 结果读取接口（供 DMA 读回）
    input wire [31:0] rd_addr,
    output reg [31:0] rd_data
);
```

### 4. vmac_top.v（顶层集成）
**职责**：连接所有子模块
**大小**：~100 行

## 重构收益

1. **代码清晰**：每个文件 100-150 行，职责单一
2. **易于展示**：可以逐模块讲解功能
3. **便于测试**：可以单独测试 DMA 控制器
4. **易于扩展**：新功能只需修改对应模块

## 实施优先级

**第一阶段**（建议立即做）：
- 提取 `vmac_regfile.v`
- 提取 `vmac_dma_controller.v`
- 创建 `vmac_top.v` 连接

**第二阶段**（可选）：
- 提取 `vmac_compute_core.v`
- 优化接口设计

## 展示效果对比

**重构前**：
- "这是 vmac_unit.v，有 437 行..."（老师：😴）

**重构后**：
- "这是配置寄存器模块，管理所有参数..." ✓
- "这是 DMA 控制器，核心创新在这里..." ✓
- "这是计算核心，执行矩阵乘法..." ✓
- 老师：👍 结构清晰！
