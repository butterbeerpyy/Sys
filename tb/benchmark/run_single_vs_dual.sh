#!/bin/bash
# run_single_vs_dual.sh
# 运行单 DMA vs 双 DMA 完整对比测试

set -e

echo "========================================"
echo "  Single DMA vs Dual DMA Benchmark"
echo "========================================"
echo ""

cd "$(dirname "$0")/../.."

# 测试单 DMA
echo "[1/2] 测试单 DMA..."
iverilog -g2012 -DTEST_SINGLE=1 -o sim/out/test_single.vvp -s benchmark_single_vs_dual_simple \
  tb/benchmark/benchmark_single_vs_dual_simple.v \
  rtl/top/p1_top.v \
  rtl/core/picorv32.v \
  rtl/mem/simple_ram.v \
  rtl/periph/vmac_unit.v \
  rtl/periph/vlm/vlm_periph.v \
  rtl/periph/vlm/vlm_preprocessing_top.v \
  rtl/periph/vlm/vlm_scanner.v \
  rtl/periph/vlm/vlm_topk_selector.v 2>&1 | grep -i error || true

timeout 300 vvp sim/out/test_single.vvp 2>&1 | tail -20

# 测试双 DMA
echo ""
echo "[2/2] 测试双 DMA..."
iverilog -g2012 -DTEST_SINGLE=0 -o sim/out/test_dual.vvp -s benchmark_single_vs_dual_simple \
  tb/benchmark/benchmark_single_vs_dual_simple.v \
  rtl/top/p1_top_dual_dma.v \
  rtl/core/picorv32.v \
  rtl/mem/dual_port_ram.v \
  rtl/mem/dual_dma_arbiter.v \
  rtl/periph/vmac_unit_dual_dma.v \
  rtl/periph/vlm/vlm_periph.v \
  rtl/periph/vlm/vlm_preprocessing_top.v \
  rtl/periph/vlm/vlm_scanner.v \
  rtl/periph/vlm/vlm_topk_selector.v 2>&1 | grep -i error || true

timeout 300 vvp sim/out/test_dual.vvp 2>&1 | tail -20

# 合并结果
echo ""
echo "[3/3] 合并结果..."
python3 - <<'EOF'
import pandas as pd

# 读取数据
single = pd.read_csv('tb/benchmark/single_dma_only.csv')
dual = pd.read_csv('tb/benchmark/dual_dma_only.csv')

# 合并
result = pd.DataFrame({
    'test_id': range(len(single)),
    'batch': single['batch'],
    'single_cycles': single['cycles'],
    'dual_cycles': dual['cycles']
})

# 计算加速比
result['speedup'] = result['single_cycles'] / result['dual_cycles']
result['improvement_pct'] = ((result['single_cycles'] - result['dual_cycles']) / result['single_cycles']) * 100

# 保存
result.to_csv('tb/benchmark/single_vs_dual_results.csv', index=False)

print("\n结果预览:")
print(result.to_string(index=False))
print(f"\n平均加速比: {result['speedup'].mean():.3f}×")
EOF

echo ""
echo "✓ 完成！结果保存到: tb/benchmark/single_vs_dual_results.csv"
echo ""
echo "运行可视化: cd tb/benchmark && python3 visualize_single_vs_dual.py"
