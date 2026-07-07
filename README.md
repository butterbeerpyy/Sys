# PicoRV32 + VMAC + VLM 集成 SoC

**一个集成了矩阵乘法和图像预处理硬件加速器的 RISC-V 系统**

[![Tests](https://img.shields.io/badge/tests-6%2F6%20passing-brightgreen)]()
[![DMA](https://img.shields.io/badge/DMA-enabled-blue)]()
[![Speedup](https://img.shields.io/badge/speedup-2.81x-orange)]()

---

## 特性

- ✅ **双硬件加速器**
  - VMAC: 8×8 矩阵乘法（支持 3D batch）
  - VLM: 112×112 图像预处理（Top-16 选择）

- ✅ **双传输模式**
  - CPU 直写：灵活调试
  - DMA 模式：高性能（2-4× 加速）

- ✅ **完整测试**
  - 6 项集成测试全部通过
  - 性能对比测试
  - 科研级可视化

---

## 快速开始

### 运行所有测试

```bash
bash run_tests.sh
```

### 性能对比 + 可视化

```bash
bash quick_start.sh
```

这会：
1. 运行所有测试
2. 生成性能数据
3. 创建科研级图表

---

## 系统架构

```
CPU (PicoRV32) ──┬── RAM (2KB) ──┬── VMAC (0x1000)
                 │                └── VLM  (0x2000)
                 │
                 └── DMA 仲裁器
```

---

## 性能数据

| 加速器 | 工作负载 | CPU 周期 | DMA 周期 | 加速比 |
|--------|----------|----------|----------|--------|
| VMAC | 8×8 矩阵 | 850 | 271 | **3.14×** |
| VMAC | 3D batch=4 | 3,600 | 950 | **3.79×** |
| VLM | 112×112 图像 | 25,100 | 12,615 | **1.99×** |

**平均加速比**: 2.81×

---

## 目录结构

```
Sys/
├── rtl/                    # RTL 源码
│   ├── core/               # PicoRV32 CPU
│   ├── mem/                # RAM
│   ├── periph/             # 外设
│   │   ├── vmac_unit.v     # 矩阵加速器
│   │   └── vlm/            # 图像加速器
│   └── top/                # 顶层集成
│
├── tb/                     # 测试平台
│   ├── benchmark/          # 性能测试 ⭐
│   └── vlm/                # VLM 测试
│
├── sim/out/                # 仿真输出
│
├── run_tests.sh            # 测试脚本
├── quick_start.sh          # 快速开始 ⭐
├── SUMMARY.md              # 项目总结 ⭐
└── README.md               # 本文件
```

---

## 使用示例

### 1. VMAC 矩阵乘法

#### CPU 模式
```c
// 配置矩阵
write_reg(VMAC_BASE + 0x20C, 8);  // m=8
write_reg(VMAC_BASE + 0x210, 8);  // n=8
write_reg(VMAC_BASE + 0x214, 8);  // k=8

// 写入矩阵 A, B (64个元素)
for (i = 0; i < 64; i++) {
    write_reg(VMAC_BASE + i*4, A[i]);
    write_reg(VMAC_BASE + 0x80 + i*4, B[i]);
}

// 触发计算
write_reg(VMAC_BASE + 0x200, 0x1);

// 等待完成
while (!(read_reg(VMAC_BASE + 0x204) & 0x1));

// 读取结果 C
for (i = 0; i < 64; i++) {
    C[i] = read_reg(VMAC_BASE + 0x100 + i*4);
}
```

#### DMA 模式
```c
// 配置矩阵
write_reg(VMAC_BASE + 0x20C, 8);  // m=8
write_reg(VMAC_BASE + 0x210, 8);  // n=8
write_reg(VMAC_BASE + 0x214, 8);  // k=8

// 配置 DMA 地址
write_reg(VMAC_BASE + 0x218, RAM_A_ADDR);
write_reg(VMAC_BASE + 0x21C, RAM_B_ADDR);
write_reg(VMAC_BASE + 0x220, RAM_C_ADDR);

// 触发 DMA
write_reg(VMAC_BASE + 0x200, 0x2);

// 等待完成（CPU 可做其他事）
while (!(read_reg(VMAC_BASE + 0x204) & 0x1));

// 结果已在 RAM_C_ADDR
```

### 2. VLM 图像预处理

#### CPU 模式
```c
// 触发 VLM
write_reg(VLM_BASE + 0x000, 0x1);

// 逐像素写入
for (i = 0; i < 12544; i++) {
    write_reg(VLM_BASE + 0x008, image[i]);
}

// 等待完成
while (!(read_reg(VLM_BASE + 0x004) & 0x1));

// 读取 Top-16 索引
for (i = 0; i < 16; i++) {
    indices[i] = read_reg(VLM_BASE + 0x100 + i*4);
}
```

#### DMA 模式
```c
// 配置源地址
write_reg(VLM_BASE + 0x00C, RAM_IMG_ADDR);

// 触发 DMA
write_reg(VLM_BASE + 0x000, 0x2);

// 等待完成（CPU 可做其他事）
while (!(read_reg(VLM_BASE + 0x004) & 0x1));

// 读取 Top-16 索引
for (i = 0; i < 16; i++) {
    indices[i] = read_reg(VLM_BASE + 0x100 + i*4);
}
```

---

## 可视化输出

运行 `bash quick_start.sh` 后，在 `tb/benchmark/` 目录查看：

1. **benchmark_comparison.png** - 主对比图
   - 绝对周期数对比
   - 加速比条形图
   - VMAC vs VLM 平均性能

2. **benchmark_heatmap.png** - 归一化热力图

3. **benchmark_throughput.png** - 吞吐量对比

4. **benchmark_comparison.pdf** - 矢量图（适合论文）

---

## 依赖

### 必需
- [Icarus Verilog](http://iverilog.icarus.com/) ≥ 12.0

### 可选（用于可视化）
- Python 3.x
- matplotlib
- seaborn
- pandas
- numpy

安装：
```bash
pip install matplotlib seaborn pandas numpy
```

---

## 测试

### 运行所有测试
```bash
bash run_tests.sh
```

输出：
```
[1/6] CPU 直写模式回归测试... ✓
[2/6] DMA 2D 模式测试...     ✓
[3/6] DMA 3D Batch 模式...   ✓
[4/6] 错误处理测试...        ✓
[5/6] VLM 预处理测试...      ✓
[6/6] VLM DMA 模式测试...    ✓

所有测试通过！
```

### 单独运行特定测试
```bash
# VMAC DMA 测试
iverilog -g2012 -o sim/out/p1_top_dma_test.vvp \
  tb/p1_top_dma_test.v rtl/top/p1_top.v ...
vvp sim/out/p1_top_dma_test.vvp

# VLM DMA 测试
iverilog -g2012 -o sim/out/p1_top_vlm_dma_test.vvp \
  tb/p1_top_vlm_dma_test.v rtl/top/p1_top.v ...
vvp sim/out/p1_top_vlm_dma_test.vvp
```

---

## 文档

- [SUMMARY.md](SUMMARY.md) - 项目完整总结
- [tb/benchmark/README.md](tb/benchmark/README.md) - 性能分析报告
- [项目进展.md](项目进展.md) - 开发日志

---

## 技术规格

| 参数 | 值 |
|------|-----|
| CPU | PicoRV32 (RISC-V RV32I) |
| 时钟 | 100 MHz (10ns) |
| RAM | 2KB (512 words) |
| VMAC | 8×8 矩阵，支持 3D batch |
| VLM | 112×112 图像，8×14 网格 |
| DMA | 1 word/cycle |

---

## 引用

**中文**:
> 实验表明，DMA 模式在矩阵乘法任务中可获得 2.5-3.8 倍加速，在图像预处理任务中可获得 2.0 倍加速，平均加速比为 2.81 倍。

**English**:
> Experiments show that DMA mode achieves 2.5-3.8× speedup for matrix operations and 2.0× speedup for image preprocessing, with an average speedup of 2.81×.

---

## 许可

本项目仅供教育和研究使用。

---

## 贡献者

硬件设计 · 系统集成 · 性能测试 · 可视化

---

**最后更新**: 2026-06-18  
**状态**: ✅ 完成并通过所有测试
