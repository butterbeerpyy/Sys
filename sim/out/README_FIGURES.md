# DMA Pipeline Performance Visualization

## Generated Figures

All figures are saved in `sim/out/` directory as high-resolution PNG files (300 DPI).

### 1. Execution Time Comparison (`pipeline_comparison_bar.png`)
- **Type**: Bar chart
- **Content**: Side-by-side comparison of execution time between serial and pipelined DMA
- **Key Findings**: 
  - 1 batch: 365 cycles (both modes)
  - 2 batches: Serial 730 vs Pipeline 379 (48.1% saved)
  - 4 batches: Serial 1460 vs Pipeline 407 (72.1% saved)

### 2. Speedup Analysis (`pipeline_speedup.png`)
- **Type**: Line chart with markers
- **Content**: Speedup factor as a function of batch count
- **Key Findings**:
  - 1 batch: 1.00× (no improvement expected)
  - 2 batches: 1.93× speedup
  - 4 batches: **3.59× speedup** 🎯

### 3. Throughput Comparison (`pipeline_throughput.png`)
- **Type**: Bar chart
- **Content**: Processing throughput measured in batches per 1000 cycles
- **Key Findings**: Pipeline mode achieves significantly higher throughput, especially with more batches

### 4. Execution Timeline (`pipeline_timeline.png`)
- **Type**: Gantt-style timeline (2 panels)
- **Content**: Visual representation of how operations overlap in pipelined execution
- **Key Insight**: Shows parallel execution of Load(batch N+1) while Compute(batch N) is running

### 5. Combined Summary (`pipeline_summary.png`)
- **Type**: 2×2 grid layout
- **Content**: 
  - (a) Execution Time
  - (b) Speedup Factor
  - (c) Efficiency Gain (% time saved)
  - (d) Hardware Utilization (estimated)
- **Best for**: Presentations and papers - shows all key metrics at a glance

## Performance Summary

| Batches | Serial (cycles) | Pipelined (cycles) | Speedup | Time Saved |
|---------|----------------|--------------------|---------|------------|
| 1       | 365            | 365                | 1.00×   | 0.0%       |
| 2       | 730            | 379                | 1.93×   | 48.1%      |
| 4       | 1460           | 407                | 3.59×   | 72.1%      |

## Key Achievements

✅ **3.59× speedup** for 4-batch workload  
✅ **72.1% reduction** in execution time (4-batch scenario)  
✅ True hardware pipelining: Load + Compute in parallel  
✅ Scalable performance: speedup increases with batch count  

## Technical Implementation

- **Double buffering**: Main + shadow register sets
- **Pipeline states**: DMA_LOAD_A_PIPE, DMA_LOAD_B_PIPE
- **State machine**: Smart batch management with buffer switching
- **Zero overhead**: No additional latency for single-batch operations

## How to Regenerate

```bash
python tb/visualize_pipeline_performance.py
```

Requirements:
- Python 3.x
- matplotlib
- numpy

## Citation

If you use these figures in your report/paper, please acknowledge:
- DMA pipeline optimization implemented in `rtl/periph/vmac_unit.v`
- Test results verified with `tb/p1_top_pipeline_debug.v`
- Visualization generated with `tb/visualize_pipeline_performance.py`
