# VLM 预处理模块集成计划

## 目标

将独立的 VLM 预处理硬件模块（位置+梯度特征）集成到主项目中，作为 VMAC 单元的可选前置模块。

## 当前状态分析

### 主项目结构
```
rtl/
├── periph/vmac_unit.v  - 矩阵加速器 (DMA + PCPI)
└── top/p1_top.v        - 顶层集成 (CPU + RAM + VMAC)

testmind/hardware/      - VLM 独立测试模块
├── simple_improved_scanner.v      - 粗扫描器 (位置+梯度)
├── multicycle_topk_selector.v     - Top-K 选择器
└── improved_pyramid_top.v         - 顶层集成
```

### VLM 模块接口
```verilog
// 扫描器
input  [7:0] pixel_in
input  pixel_valid
output [7:0] interest_out [0:63]  // 8x8 grid
output done

// Top-K 选择器
input  [7:0] values [0:63]
output [5:0] topk_indices [0:15]
output done
```

### VMAC 单元接口
```verilog
// 内存接口 (0x0000_1000)
input  valid, addr[31:0], wdata[31:0], wstrb[3:0]
output ready, rdata[31:0]

// DMA 接口
output dma_valid, dma_we, dma_addr[31:0], dma_wdata[31:0]
input  dma_ready, dma_rdata[31:0], dma_active
```

## 集成方案

### 方案选择：**渐进式集成**

**第一阶段**（本次实施）：模块迁移 + 独立测试
- 移动模块到主项目目录
- 重命名以符合项目规范
- 创建独立测试平台
- 验证功能不变

**第二阶段**（可选，未来）：与 VMAC 集成
- 添加配置寄存器
- 实现 DMA 数据通路
- 端到端测试

**理由**：
- ✅ 降低风险，不影响现有 VMAC 功能
- ✅ 保持模块独立性，便于调试
- ✅ 可单独展示 VLM 功能

## 实施步骤

### Step 1: 创建目录结构
```
rtl/periph/vlm/
├── vlm_scanner.v              (重命名自 simple_improved_scanner.v)
├── vlm_topk_selector.v        (重命名自 multicycle_topk_selector.v)
└── vlm_preprocessing_top.v    (重命名自 improved_pyramid_top.v)
```

### Step 2: 模块重命名与规范化

**命名规范**：
- `simple_improved_scanner` → `vlm_scanner`
- `multicycle_topk_selector` → `vlm_topk_selector`
- `improved_pyramid_top` → `vlm_preprocessing_top`

**接口规范化**：
- 添加统一的复位信号 `rst_n`
- 统一时钟信号 `clk`
- 添加参数配置

### Step 3: 创建测试平台

```
tb/vlm/
├── vlm_scanner_tb.v              - 扫描器单元测试
├── vlm_topk_selector_tb.v        - Top-K 选择器测试
└── vlm_preprocessing_tb.v        - 集成测试
```

**测试数据**：
- 使用 `testmind/hardware/test_image.hex`
- 对比预期输出索引

### Step 4: 集成到构建系统

**更新 `run_tests.sh`**：
```bash
# VLM Preprocessing Tests
echo "Running VLM preprocessing tests..."
iverilog -g2012 -o sim/out/vlm_scanner_tb.vvp \
    rtl/periph/vlm/vlm_scanner.v \
    tb/vlm/vlm_scanner_tb.v
vvp sim/out/vlm_scanner_tb.vvp
```

### Step 5: 文档更新

**更新 `项目进展.md`**：
- 添加 VLM 模块位置
- 更新测试覆盖情况
- 记录集成状态

## 验证计划

### 单元测试
1. **vlm_scanner_tb.v**：
   - 输入：112x112 dog.jpg (test_image.hex)
   - 验证：64 个兴趣度值正确
   - 检查：中心权重 > 边缘权重

2. **vlm_topk_selector_tb.v**：
   - 输入：预定义的 64 个值
   - 验证：输出 Top-16 索引正确
   - 检查：排序逻辑

3. **vlm_preprocessing_tb.v**：
   - 端到端测试
   - 输入：dog.jpg
   - 输出：16 个索引
   - 验证：与 `testmind/hardware` 结果一致

### 集成验证

使用 Python 可视化脚本验证：
```bash
cd rtl/periph/vlm
iverilog -g2012 -o test.vvp *.v ../../../tb/vlm/vlm_preprocessing_tb.v
vvp test.vvp
python ../../../testmind/hardware/visualize_result.py \
    ../../../testmind/real_images/dog.jpg \
    output_indices.hex \
    result_integrated.png 14 8
```

**通过标准**：
- ✅ `result_integrated.png` 绿框集中在中心（狗）
- ✅ 索引与独立测试一致
- ✅ 无仿真警告/错误

## 文件清单

### 新增文件
```
rtl/periph/vlm/
├── vlm_scanner.v              (122 行)
├── vlm_topk_selector.v        (94 行)
└── vlm_preprocessing_top.v    (57 行)

tb/vlm/
├── vlm_scanner_tb.v           (约 80 行)
├── vlm_topk_selector_tb.v     (约 60 行)
└── vlm_preprocessing_tb.v     (约 100 行)
```

### 修改文件
```
run_tests.sh                   (添加 VLM 测试)
项目进展.md                    (更新集成状态)
```

## 时间估算

| 任务 | 预计时间 |
|------|---------|
| 创建目录、移动文件 | 10 分钟 |
| 模块重命名与清理 | 20 分钟 |
| 创建单元测试 | 30 分钟 |
| 集成测试与验证 | 30 分钟 |
| 文档更新 | 10 分钟 |
| **总计** | **1.5-2 小时** |

## 风险与缓解

| 风险 | 影响 | 缓解措施 |
|------|------|---------|
| 模块重命名导致接口不匹配 | 中 | 先复制再修改，保留原文件 |
| 测试数据路径问题 | 低 | 使用相对路径，添加存在性检查 |
| 仿真工具版本差异 | 低 | 使用相同的 iverilog 命令 |
| 原有功能受影响 | 高 | 不修改 `vmac_unit.v`，完全独立 |

## 成功标准

✅ **必须达成**：
1. 所有 3 个模块通过单元测试
2. 集成测试生成正确的可视化结果（狗在中心）
3. 与 `testmind/hardware` 的输出完全一致
4. 无编译警告或错误

✅ **可选目标**（第二阶段）：
- 与 VMAC 单元的 DMA 集成
- 添加配置寄存器
- CPU 可控的预处理流程

## 下一步行动

1. 创建目录 `rtl/periph/vlm/` 和 `tb/vlm/`
2. 复制模块文件并重命名
3. 创建第一个测试：`vlm_scanner_tb.v`
4. 编译并验证
5. 逐步完成其他模块
