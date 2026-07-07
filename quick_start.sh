#!/bin/bash
# Quick Start Guide for CPU vs DMA Benchmark

set -e

echo "=========================================="
echo "  CPU vs DMA Performance Benchmark"
echo "  Quick Start Guide"
echo "=========================================="
echo ""

# 检查环境
echo "[1/4] Checking environment..."
if ! command -v iverilog &> /dev/null; then
    echo "❌ Error: iverilog not found. Please install Icarus Verilog."
    exit 1
fi

if ! command -v python3 &> /dev/null && ! command -v python &> /dev/null; then
    echo "⚠️  Warning: Python not found. Visualization will be skipped."
    PYTHON_OK=0
else
    PYTHON_OK=1
fi

echo "✓ Environment ready"
echo ""

# 运行所有测试
echo "[2/4] Running all tests..."
bash run_tests.sh
echo ""

# 检查 Python 包
if [ $PYTHON_OK -eq 1 ]; then
    echo "[3/4] Checking Python packages..."

    PYTHON_CMD=$(command -v python3 || command -v python)

    if $PYTHON_CMD -c "import matplotlib, seaborn, pandas" 2>/dev/null; then
        echo "✓ All packages available"

        echo ""
        echo "[4/4] Generating visualizations..."
        cd tb/benchmark
        $PYTHON_CMD visualize_benchmark.py
        cd ../..

        echo ""
        echo "=========================================="
        echo "  ✅ Benchmark Complete!"
        echo "=========================================="
        echo ""
        echo "Results:"
        echo "  • CSV data: tb/benchmark/benchmark_results.csv"
        echo "  • Main plot: tb/benchmark/benchmark_comparison.png"
        echo "  • Heatmap: tb/benchmark/benchmark_heatmap.png"
        echo "  • Throughput: tb/benchmark/benchmark_throughput.png"
        echo "  • PDF (paper): tb/benchmark/benchmark_comparison.pdf"
        echo ""
        echo "Open images to view the results!"

    else
        echo "⚠️  Missing packages. Install with:"
        echo "    pip install matplotlib seaborn pandas numpy"
        echo ""
        echo "Skipping visualization..."

        echo ""
        echo "=========================================="
        echo "  ⚠️  Tests Complete, Visualization Skipped"
        echo "=========================================="
        echo ""
        echo "Results:"
        echo "  • CSV data: tb/benchmark/benchmark_results.csv"
        echo ""
        echo "Install Python packages to generate plots."
    fi
else
    echo "[3/4] Python not available, skipping visualization"
    echo "[4/4] Done"

    echo ""
    echo "=========================================="
    echo "  ⚠️  Tests Complete, Visualization Skipped"
    echo "=========================================="
fi

echo ""
echo "For detailed analysis, see:"
echo "  • tb/benchmark/README.md"
echo "  • SUMMARY.md"
echo ""
