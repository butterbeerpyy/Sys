# VLM 特化硬件实现计划

## 🎯 目标

实现完整的"图片输入 → 硬件仿真 → 图片输出"流程

## 📐 系统架构

```
[Python 前端]
    ↓ 图片转像素数据
[Verilog 硬件]
  ├── 粗扫描器 (Coarse Scanner)
  ├── Top-K 选择器 (Top-K Selector)
  └── 索引输出
    ↓ 选中的 patch 索引
[Python 后端]
    ↓ 可视化
[输出图片]
```

## 🔧 需要实现的模块

### 1. vmac_coarse_scanner.v
**功能**：快速边缘检测（粗扫描）
```verilog
输入：224×224 图像（逐行输入）
输出：16×16 兴趣度图（每个值 8-16 bit）
硬件：Sobel 边缘检测器
```

**复杂度**：★★☆☆☆（中等）
**时间**：2-3 天

### 2. vmac_topk_selector.v
**功能**：硬件 Top-K 选择（排序）
```verilog
输入：16×16 = 256 个值
输出：Top-60 的索引（60 × 8bit）
硬件：比较树 / 插入排序
```

**复杂度**：★★★★☆（较难）
**时间**：3-4 天

### 3. pyramid_top.v
**功能**：顶层集成
```verilog
集成：扫描器 + 选择器
接口：AXI-Stream / 简单握手
```

**复杂度**：★★☆☆☆（简单）
**时间**：1 天

### 4. Python 包装
**功能**：图片 ↔ 硬件 ↔ 可视化
```python
img_to_verilog.py    # 图片 → hex 文件
run_simulation.py    # 调用 iverilog
verilog_to_img.py    # 结果 → 可视化图片
```

**复杂度**：★★☆☆☆（中等）
**时间**：2 天

## 📅 实施计划（10 天）

### Phase 1：粗扫描器（Day 1-3）
- Day 1：设计 Sobel 边缘检测模块
- Day 2：实现扫描器，写 testbench
- Day 3：验证和调试

### Phase 2：Top-K 选择器（Day 4-6）
- Day 4：设计比较树架构
- Day 5：实现选择器，写 testbench
- Day 6：验证和优化

### Phase 3：集成和 Python 包装（Day 7-8）
- Day 7：顶层集成，完整仿真
- Day 8：Python 包装脚本

### Phase 4：端到端测试（Day 9-10）
- Day 9：完整流程测试，多场景验证
- Day 10：优化和文档

## 📊 预期效果

### 演示流程
```bash
# 一键运行
python demo_hardware.py --input dog.jpg --output result.png

# 背后发生：
1. Python 读图片 → test.hex
2. iverilog 仿真 → output.hex
3. Python 可视化 → result.png

# 用户看到：
输入图片 → [硬件处理中...] → 输出图片（高亮选中区域）
同时生成波形：waveform.vcd
```

### 答辩展示价值
✅ 真实硬件实现（不只是 Python 模拟）
✅ 可视化效果（老师能直观看到）
✅ 波形验证（证明硬件正确工作）
✅ 性能数据（周期数、资源占用）

## 🎯 关键技术点

### 1. 图像数据输入
```verilog
// 简化方案：从文件读取（testbench）
initial begin
    $readmemh("test_image.hex", image_mem);
end
```

### 2. 边缘检测
```verilog
// 3×3 Sobel 算子（硬化）
wire [7:0] gx = abs((-1)*p00 + 0*p01 + 1*p02 + 
                    (-2)*p10 + 0*p11 + 2*p12 +
                    (-1)*p20 + 0*p21 + 1*p22);
// 类似计算 gy，然后 magnitude = gx + gy
```

### 3. Top-K 选择
```verilog
// 方案 A：插入排序（面积小，周期多）
// 方案 B：比较树（面积大，周期少）
// 推荐：插入排序（实现简单）
```

### 4. Python 可视化
```python
# 读取硬件输出的索引
selected_indices = read_hex("output.hex")

# 在原图上画框
for idx in selected_indices:
    y = (idx // 16) * 14
    x = (idx % 16) * 14
    draw_rectangle(img, x, y, 14, 14, color='green')
```

## 📝 文件结构

```
rtl/periph/
├── pyramid_coarse_scanner.v    # 粗扫描器
├── pyramid_topk_selector.v     # Top-K 选择器
├── pyramid_top.v               # 顶层
└── pyramid_defines.vh          # 参数定义

tb/
├── pyramid_scanner_tb.v        # 扫描器测试
├── pyramid_topk_tb.v           # 选择器测试
├── pyramid_top_tb.v            # 完整测试
└── test_image.hex              # 测试图像数据

testmind/hardware/
├── img_to_hex.py              # 图片 → hex
├── run_simulation.py          # 运行仿真
├── visualize_result.py        # hex → 图片
└── demo_hardware.py           # 一键演示脚本
```

## 💡 实现建议

### 简化策略
1. **输入简化**：使用灰度图（单通道）而非 RGB
2. **分辨率简化**：先做 112×112，成功后扩展到 224×224
3. **Top-K 简化**：先做 Top-16，再扩展到 Top-60

### 验证策略
1. **单元测试**：每个模块独立验证
2. **集成测试**：顶层功能验证
3. **对比测试**：Verilog 输出 vs Python 输出（应该一致）

## 🚀 下一步

准备开始吗？我可以帮你：

1. **立即开始**：从粗扫描器开始实现
2. **先看示例**：我先写一个简化版的扫描器让你看看
3. **调整计划**：你有什么想法或担心的地方？

告诉我你的选择！
