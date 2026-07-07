# Mini Pyramid Processor - Hardware Demo

## 🎯 这是什么

一个**最小可行版本**的金字塔处理器硬件实现，用于验证完整流程。

**规模**：
- 图像：32×32 像素（灰度）
- Patches：4×4 = 16 个
- 选择：Top-4

## 🚀 快速开始

### 一键运行

```bash
cd testmind/hardware
python demo.py
```

或指定输入图像：

```bash
python demo.py ../../path/to/image.jpg
```

### 分步运行

```bash
# Step 1: 图片转 hex
python img_to_hex.py input.jpg

# Step 2: 硬件仿真
python run_simulation.py

# Step 3: 可视化
python visualize_result.py input.jpg
```

## 📁 文件说明

### Verilog 硬件模块

- `mini_coarse_scanner.v` - 粗扫描器（边缘检测）
- `mini_topk_selector.v` - Top-K 选择器（排序）
- `mini_pyramid_top.v` - 顶层集成
- `mini_pyramid_tb.v` - 测试平台

### Python 脚本

- `img_to_hex.py` - 图片 → hex 转换
- `run_simulation.py` - 运行 iverilog 仿真
- `visualize_result.py` - 结果可视化
- `demo.py` - 一键演示

## 🎨 完整流程

```
输入图片 (32×32)
    ↓
[img_to_hex.py]
    ↓
test_image.hex (1024 字节)
    ↓
[Verilog 硬件仿真]
  ├── mini_coarse_scanner → 计算 16 个兴趣度值
  └── mini_topk_selector → 选择 Top-4
    ↓
output_indices.hex (4 个索引)
    ↓
[visualize_result.py]
    ↓
result_hardware.png (带绿框高亮)
```

## 📊 预期输出

### 终端输出示例

```
======================================================================
  MINI PYRAMID PROCESSOR - HARDWARE DEMONSTRATION
======================================================================

[Step 1/3] Converting image to hex...
✅ Converted ../real_images/dog.jpg to test_image.hex
   Image size: 32x32 = 1024 pixels

[Step 2/3] Running hardware simulation...
✅ Compilation successful
✅ Simulation complete

Simulation output:
=== Top-4 Selected Indices ===
Index 0: 5
Index 1: 6
Index 2: 9
Index 3: 10
Simulation complete!

[Step 3/3] Visualizing results...
✅ Read 4 selected indices
   Indices: [5, 6, 9, 10]
✅ Saved visualization to: result_hardware.png

======================================================================
  ✅ SUCCESS!
======================================================================
```

### 生成的文件

- `result_hardware.png` - 最终可视化（原图 + 绿框）
- `mini_pyramid.vcd` - 波形文件
- `test_image.hex` - 输入数据
- `output_indices.hex` - 硬件输出

## 🔍 验证正确性

### 对比测试

可以运行 Python 版本对比：

```python
# Python 软件版本
python ../test_pyramid.py

# 硬件版本
python demo.py

# 对比索引是否一致
```

### 查看波形

```bash
gtkwave mini_pyramid.vcd
```

关键信号：
- `dut.u_scanner.interest_out` - 兴趣度值
- `dut.selected_indices` - 最终输出

## ⚠️ 限制和简化

这是 **mini 验证版本**，有以下简化：

1. **尺寸小**：32×32（完整版应该是 224×224）
2. **单周期排序**：Top-K 选择器是单周期的（实际应该多周期）
3. **简化梯度**：只取中心点梯度（完整版应该是 3×3 Sobel）
4. **灰度图**：只有一个通道（RGB 需要 3 个）

## 🎯 下一步扩展

验证成功后，可以扩展：

1. **扩大规模**：32×32 → 112×112 → 224×224
2. **增加 Top-K**：4 → 20 → 60
3. **完整 Sobel**：实现真正的 3×3 卷积
4. **多周期设计**：Top-K 选择器分多周期完成
5. **RGB 支持**：3 通道输入

## 📝 技术要点

### 边缘检测

简化的梯度计算：
```verilog
gx = p01 - p00  // 水平梯度
gy = p11 - p10  // 垂直梯度
interest = |gx| + |gy|
```

### Top-K 选择

插入排序算法：
- 维护 Top-K 数组
- 遍历所有值，插入到正确位置
- 时间复杂度：O(N×K)

### 数据流

1. 逐像素输入（串行）
2. 缓存到内部 buffer
3. 并行计算所有 patch
4. 输出 Top-K 索引

## 🐛 故障排查

### 编译错误

```bash
# 检查 iverilog 是否安装
iverilog -v

# 检查语法
iverilog -g2012 -t null mini_pyramid_top.v
```

### 仿真卡住

- 检查 `test_image.hex` 是否存在
- 查看波形：`gtkwave mini_pyramid.vcd`
- 检查超时设置（testbench 中）

### 输出异常

- 对比 Python 软件版本
- 检查兴趣度计算逻辑
- 验证 Top-K 排序算法

## 💡 给老师演示时

1. **运行演示**：`python demo.py`
2. **展示输出图**：打开 `result_hardware.png`
3. **展示波形**：`gtkwave mini_pyramid.vcd`（如果老师想看细节）
4. **讲解流程**：指着代码讲 3 个模块的作用

**重点强调**：
- 这是真实硬件仿真，不是软件模拟
- 图片进 → 硬件处理 → 图片出
- 可以扩展到完整版本
