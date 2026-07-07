#!/bin/bash
# DMA 项目测试脚本

set -e

echo "========================================="
echo "  DMA 项目回归测试"
echo "========================================="

VLM_MODULES="rtl/periph/vlm/vlm_periph.v rtl/periph/vlm/vlm_preprocessing_top.v rtl/periph/vlm/vlm_scanner.v rtl/periph/vlm/vlm_topk_selector.v"

# 测试 1: 原有 CPU 直写模式 (8 轮随机测试)
echo ""
echo "[1/6] 运行 CPU 直写模式回归测试..."
iverilog -g2012 -o sim/out/p1_top_tb.vvp -s p1_top_tb \
  tb/p1_top_tb.v \
  rtl/top/p1_top.v \
  rtl/core/picorv32.v \
  rtl/mem/simple_ram.v \
  rtl/periph/vmac_unit.v \
  $VLM_MODULES

vvp sim/out/p1_top_tb.vvp > sim/out/p1_top_tb.log 2>&1

if grep -q "PASS: randomized 8x8 regression completed" sim/out/p1_top_tb.log; then
    echo "✓ CPU 直写模式测试通过 (8 trials)"
else
    echo "✗ CPU 直写模式测试失败"
    tail -20 sim/out/p1_top_tb.log
    exit 1
fi

# 测试 2: DMA 模式测试
echo ""
echo "[2/6] 运行 DMA 模式测试 (2D)..."
iverilog -g2012 -o sim/out/p1_top_dma_test.vvp -s p1_top_dma_test \
  tb/p1_top_dma_test.v \
  rtl/top/p1_top.v \
  rtl/core/picorv32.v \
  rtl/mem/simple_ram.v \
  rtl/periph/vmac_unit.v \
  $VLM_MODULES

vvp sim/out/p1_top_dma_test.vvp > sim/out/p1_top_dma_test.log 2>&1

if grep -q "PASS: DMA mode test completed successfully" sim/out/p1_top_dma_test.log; then
    echo "✓ DMA 模式测试通过"
else
    echo "✗ DMA 模式测试失败"
    tail -20 sim/out/p1_top_dma_test.log
    exit 1
fi

# 测试 3: 3D Batch 模式测试
echo ""
echo "[3/6] 运行 3D Batch 模式测试..."
iverilog -g2012 -o sim/out/p1_top_3d_test.vvp -s p1_top_3d_test \
  tb/p1_top_3d_test.v \
  rtl/top/p1_top.v \
  rtl/core/picorv32.v \
  rtl/mem/simple_ram.v \
  rtl/periph/vmac_unit.v \
  $VLM_MODULES

vvp sim/out/p1_top_3d_test.vvp > sim/out/p1_top_3d_test.log 2>&1

if grep -q "PASS: 3D batch test completed successfully" sim/out/p1_top_3d_test.log; then
    echo "✓ 3D Batch 模式测试通过"
else
    echo "✗ 3D Batch 模式测试失败"
    tail -20 sim/out/p1_top_3d_test.log
    exit 1
fi

# 测试 4: 错误处理测试
echo ""
echo "[4/6] 运行错误处理测试..."
iverilog -g2012 -o sim/out/p1_top_error_test.vvp -s p1_top_error_test \
  tb/p1_top_error_test.v \
  rtl/top/p1_top.v \
  rtl/core/picorv32.v \
  rtl/mem/simple_ram.v \
  rtl/periph/vmac_unit.v \
  $VLM_MODULES

vvp sim/out/p1_top_error_test.vvp > sim/out/p1_top_error_test.log 2>&1

if grep -q "All error handling tests passed" sim/out/p1_top_error_test.log; then
    echo "✓ 错误处理测试通过"
else
    echo "✗ 错误处理测试失败"
    tail -20 sim/out/p1_top_error_test.log
    exit 1
fi

# 测试 5: VLM 预处理模块测试
echo ""
echo "[5/6] 运行 VLM 预处理模块测试..."
iverilog -g2012 -o sim/out/vlm_preprocessing_tb.vvp -s vlm_preprocessing_tb \
  tb/vlm/vlm_preprocessing_tb.v \
  rtl/periph/vlm/vlm_scanner.v \
  rtl/periph/vlm/vlm_topk_selector.v \
  rtl/periph/vlm/vlm_preprocessing_top.v

vvp sim/out/vlm_preprocessing_tb.vvp > sim/out/vlm_preprocessing_tb.log 2>&1

if grep -q "Simulation complete" sim/out/vlm_preprocessing_tb.log; then
    echo "✓ VLM 预处理模块测试通过"
else
    echo "✗ VLM 预处理模块测试失败"
    tail -20 sim/out/vlm_preprocessing_tb.log
    exit 1
fi

# 总结
echo ""
echo "========================================="
echo "  所有测试通过！"
echo "========================================="
echo ""
# 测试 6: VLM DMA 模式测试
echo ""
echo "[6/6] 运行 VLM DMA 模式测试..."
iverilog -g2012 -o sim/out/p1_top_vlm_dma_test.vvp -s p1_top_vlm_dma_test \
  tb/p1_top_vlm_dma_test.v \
  rtl/top/p1_top.v \
  rtl/core/picorv32.v \
  rtl/mem/simple_ram.v \
  rtl/periph/vmac_unit.v \
  $VLM_MODULES

vvp sim/out/p1_top_vlm_dma_test.vvp > sim/out/p1_top_vlm_dma_test.log 2>&1

if grep -q "PASS: VLM DMA Mode Test Completed" sim/out/p1_top_vlm_dma_test.log; then
    echo "✓ VLM DMA 模式测试通过"
else
    echo "✗ VLM DMA 模式测试失败"
    tail -20 sim/out/p1_top_vlm_dma_test.log
    exit 1
fi

echo "详细日志："
echo "  - sim/out/p1_top_tb.log"
echo "  - sim/out/p1_top_dma_test.log"
echo "  - sim/out/p1_top_3d_test.log"
echo "  - sim/out/p1_top_error_test.log"
echo "  - sim/out/vlm_preprocessing_tb.log"
echo ""
echo "波形文件："
echo "  - sim/out/p1_top_tb.vcd"
echo "  - sim/out/p1_top_dma_test.vcd"
echo "  - sim/out/p1_top_3d_test.vcd"
echo "  - sim/out/p1_top_error_test.vcd"
echo "  - sim/out/vlm_preprocessing_tb.vcd (in tb/vlm/)"
echo ""
