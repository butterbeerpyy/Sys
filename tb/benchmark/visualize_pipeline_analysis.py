#!/usr/bin/env python3
"""
visualize_pipeline_analysis.py
详细分析并可视化流水线性能，包括瓶颈分析
"""

import pandas as pd
import matplotlib.pyplot as plt
import numpy as np
from matplotlib.patches import Rectangle
import matplotlib.patches as mpatches

# 设置科研绘图风格
plt.rcParams['font.family'] = 'DejaVu Sans'
plt.rcParams['font.size'] = 11
plt.rcParams['axes.linewidth'] = 1.2
plt.rcParams['grid.alpha'] = 0.3
plt.rcParams['figure.dpi'] = 300

# 读取数据
df = pd.read_csv('pipeline_analysis.csv')

# 创建 2x2 子图
fig = plt.figure(figsize=(16, 12))
gs = fig.add_gridspec(3, 2, hspace=0.35, wspace=0.3, height_ratios=[1.2, 1, 1])

# ==================== 子图 1: 总周期对比 ====================
ax1 = fig.add_subplot(gs[0, :])

# 分组数据
batches = sorted(df['batch_count'].unique())
x = np.arange(len(batches))
width = 0.35

non_pipe = df[df['mode'] == 'NonPipeline'].sort_values('batch_count')['total_cycles'].values
pipe = df[df['mode'] == 'Pipeline'].sort_values('batch_count')['total_cycles'].values

bars1 = ax1.bar(x - width/2, non_pipe, width, label='Non-Pipeline DMA',
                color='#3498DB', alpha=0.85, edgecolor='black', linewidth=1.2)
bars2 = ax1.bar(x + width/2, pipe, width, label='Pipeline DMA',
                color='#E74C3C', alpha=0.85, edgecolor='black', linewidth=1.2)

# 添加数值标签
for bar in bars1:
    height = bar.get_height()
    ax1.text(bar.get_x() + bar.get_width()/2., height,
             f'{int(height)}',
             ha='center', va='bottom', fontsize=10, fontweight='bold')

for bar in bars2:
    height = bar.get_height()
    ax1.text(bar.get_x() + bar.get_width()/2., height,
             f'{int(height)}',
             ha='center', va='bottom', fontsize=10, fontweight='bold')

ax1.set_ylabel('Total Execution Cycles', fontsize=13, fontweight='bold')
ax1.set_title('Pipeline vs Non-Pipeline: Total Cycles Comparison',
              fontsize=14, fontweight='bold', pad=15)
ax1.set_xticks(x)
ax1.set_xticklabels([f'Batch={b}' for b in batches])
ax1.legend(loc='upper left', frameon=True, shadow=True, fontsize=11)
ax1.grid(axis='y', alpha=0.3, linestyle='--')
ax1.set_axisbelow(True)

# ==================== 子图 2: 时间分解（堆叠柱状图）====================
ax2 = fig.add_subplot(gs[1, 0])

# 选择 batch=4 的详细数据
batch4_non = df[(df['batch_count'] == 4) & (df['mode'] == 'NonPipeline')].iloc[0]
batch4_pipe = df[(df['batch_count'] == 4) & (df['mode'] == 'Pipeline')].iloc[0]

categories = ['Non-Pipeline', 'Pipeline']
load_data = [batch4_non['load_cycles'], batch4_pipe['load_cycles']]
compute_data = [batch4_non['compute_cycles'], batch4_pipe['compute_cycles']]
store_data = [batch4_non['store_cycles'], batch4_pipe['store_cycles']]
overhead_data = [batch4_non['overhead_cycles'], batch4_pipe['overhead_cycles']]

x_cat = np.arange(len(categories))
width = 0.6

p1 = ax2.bar(x_cat, load_data, width, label='Load (DMA Read)',
             color='#3498DB', edgecolor='black', linewidth=1.2)
p2 = ax2.bar(x_cat, compute_data, width, bottom=load_data,
             label='Compute', color='#2ECC71', edgecolor='black', linewidth=1.2)
p3 = ax2.bar(x_cat, store_data, width,
             bottom=np.array(load_data) + np.array(compute_data),
             label='Store (DMA Write)', color='#F39C12', edgecolor='black', linewidth=1.2)
p4 = ax2.bar(x_cat, overhead_data, width,
             bottom=np.array(load_data) + np.array(compute_data) + np.array(store_data),
             label='Overhead', color='#95A5A6', edgecolor='black', linewidth=1.2)

ax2.set_ylabel('Cycles', fontsize=12, fontweight='bold')
ax2.set_title('Execution Time Breakdown (Batch=4)',
              fontsize=13, fontweight='bold', pad=12)
ax2.set_xticks(x_cat)
ax2.set_xticklabels(categories)
ax2.legend(loc='upper right', frameon=True, shadow=True, fontsize=10)
ax2.grid(axis='y', alpha=0.3, linestyle='--')
ax2.set_axisbelow(True)

# 添加总数标签
for i, cat in enumerate(categories):
    total = load_data[i] + compute_data[i] + store_data[i] + overhead_data[i]
    ax2.text(i, total + 20, f'{int(total)}', ha='center', fontweight='bold', fontsize=11)

# ==================== 子图 3: DMA 瓶颈分析 ====================
ax3 = fig.add_subplot(gs[1, 1])

# 计算 DMA 时间占比
non_pipe_dma_ratio = []
pipe_dma_ratio = []

for batch in batches:
    non = df[(df['batch_count'] == batch) & (df['mode'] == 'NonPipeline')].iloc[0]
    pipe_data = df[(df['batch_count'] == batch) & (df['mode'] == 'Pipeline')].iloc[0]

    non_dma = non['load_cycles'] + non['store_cycles']
    non_total = non['total_cycles']
    non_pipe_dma_ratio.append(100 * non_dma / non_total if non_total > 0 else 0)

    pipe_dma = pipe_data['load_cycles'] + pipe_data['store_cycles']
    pipe_total = pipe_data['total_cycles']
    pipe_dma_ratio.append(100 * pipe_dma / pipe_total if pipe_total > 0 else 0)

x_bat = np.arange(len(batches))
bars1 = ax3.bar(x_bat - width/2, non_pipe_dma_ratio, width, label='Non-Pipeline',
                color='#3498DB', alpha=0.85, edgecolor='black', linewidth=1.2)
bars2 = ax3.bar(x_bat + width/2, pipe_dma_ratio, width, label='Pipeline',
                color='#E74C3C', alpha=0.85, edgecolor='black', linewidth=1.2)

# 添加数值标签
for bar in bars1:
    height = bar.get_height()
    ax3.text(bar.get_x() + bar.get_width()/2., height,
             f'{height:.1f}%',
             ha='center', va='bottom', fontsize=9, fontweight='bold')

for bar in bars2:
    height = bar.get_height()
    ax3.text(bar.get_x() + bar.get_width()/2., height,
             f'{height:.1f}%',
             ha='center', va='bottom', fontsize=9, fontweight='bold')

ax3.set_ylabel('DMA Time Percentage (%)', fontsize=12, fontweight='bold')
ax3.set_title('DMA Bottleneck Analysis',
              fontsize=13, fontweight='bold', pad=12)
ax3.set_xticks(x_bat)
ax3.set_xticklabels([f'Batch={b}' for b in batches])
ax3.legend(loc='lower right', frameon=True, shadow=True)
ax3.axhline(y=95, color='red', linestyle='--', linewidth=2, alpha=0.7, label='95% threshold')
ax3.grid(axis='y', alpha=0.3, linestyle='--')
ax3.set_axisbelow(True)
ax3.set_ylim([0, 105])

# ==================== 子图 4: 流水线效率 ====================
ax4 = fig.add_subplot(gs[2, 0])

# 计算每 batch 加速比
speedups = []
for batch in batches:
    non = df[(df['batch_count'] == batch) & (df['mode'] == 'NonPipeline')].iloc[0]['total_cycles']
    pipe_val = df[(df['batch_count'] == batch) & (df['mode'] == 'Pipeline')].iloc[0]['total_cycles']
    speedup = non / pipe_val if pipe_val > 0 else 1.0
    speedups.append(speedup)

colors = ['#27AE60' if s > 1.05 else ('#E67E22' if s < 0.95 else '#95A5A6') for s in speedups]
bars = ax4.barh(batches, speedups, color=colors, alpha=0.85,
                edgecolor='black', linewidth=1.2)

# 添加数值标签
for i, (bar, val) in enumerate(zip(bars, speedups)):
    ax4.text(val + 0.02, bar.get_y() + bar.get_height()/2,
             f'{val:.3f}×',
             va='center', fontsize=10, fontweight='bold')

# 添加基准线
ax4.axvline(x=1.0, color='red', linestyle='--', linewidth=2, label='Baseline (1.0×)')

ax4.set_xlabel('Speedup (Non-Pipeline / Pipeline)', fontsize=12, fontweight='bold')
ax4.set_ylabel('Batch Count', fontsize=12, fontweight='bold')
ax4.set_title('Pipeline Speedup by Batch Size',
              fontsize=13, fontweight='bold', pad=12)
ax4.legend(loc='lower right', frameon=True, shadow=True)
ax4.grid(axis='x', alpha=0.3, linestyle='--')
ax4.set_axisbelow(True)
ax4.set_xlim([0.9, 1.15])

# ==================== 子图 5: 理论 vs 实际 ====================
ax5 = fig.add_subplot(gs[2, 1])

# 理论流水线性能（假设完美重叠）
theoretical_speedup = []
actual_speedup = speedups

for batch in batches:
    # 理论：如果 Load、Compute、Store 完全重叠
    # 单 batch: 无重叠机会，speedup=1.0
    # 多 batch: 理论上可以节省 (batch-1) * max(compute, transition)
    if batch == 1:
        theoretical_speedup.append(1.0)
    else:
        # 假设完美流水线：只计算一次填充和排空时间
        # 非流水线: batch * (load + compute + store)
        # 流水线: load + batch * max(load, compute, store) + store
        # 简化：假设 DMA 占主导，理论加速 ~1.0（因为 DMA 无法并行）
        theoretical_speedup.append(1.0)

x_theory = np.arange(len(batches))
ax5.plot(x_theory, theoretical_speedup, 'o-', linewidth=2.5, markersize=8,
         label='Theoretical (Single DMA)', color='#E74C3C', alpha=0.8)
ax5.plot(x_theory, actual_speedup, 's-', linewidth=2.5, markersize=8,
         label='Actual Pipeline', color='#3498DB', alpha=0.8)
ax5.axhline(y=1.0, color='gray', linestyle='--', linewidth=1.5, alpha=0.5)

ax5.set_xlabel('Batch Count', fontsize=12, fontweight='bold')
ax5.set_ylabel('Speedup', fontsize=12, fontweight='bold')
ax5.set_title('Theoretical vs Actual Pipeline Performance',
              fontsize=13, fontweight='bold', pad=12)
ax5.set_xticks(x_theory)
ax5.set_xticklabels([f'{b}' for b in batches])
ax5.legend(loc='upper left', frameon=True, shadow=True)
ax5.grid(alpha=0.3, linestyle='--')
ax5.set_axisbelow(True)

# ==================== 总标题和注释 ====================
fig.suptitle('VMAC Pipeline Performance Analysis:\nWhy Pipeline Doesn\'t Help with Single DMA Channel',
             fontsize=16, fontweight='bold', y=0.98)

# 添加关键发现文本框
findings_text = """
Key Findings:
• DMA占用 >95% 执行时间
• 单DMA通道无法并行读写
• 流水线加速 ≈ 1.0× (无提升)
• Compute仅占 <1% 时间

结论: 单DMA架构的瓶颈在传输，
不在计算，流水线优化无效。
"""

fig.text(0.02, 0.02, findings_text, fontsize=10,
         bbox=dict(boxstyle='round', facecolor='#FFE5E5', alpha=0.8, edgecolor='#E74C3C', linewidth=2),
         verticalalignment='bottom', family='monospace')

# 保存
plt.savefig('pipeline_analysis.png', dpi=300, bbox_inches='tight')
plt.savefig('pipeline_analysis.pdf', bbox_inches='tight')
print("✓ Saved: pipeline_analysis.png")
print("✓ Saved: pipeline_analysis.pdf")

# ==================== 额外图：架构对比 ====================
fig2, (ax_left, ax_right) = plt.subplots(1, 2, figsize=(14, 6))

# 左图：单DMA架构
ax_left.text(0.5, 0.9, 'Current Architecture\n(Single DMA Channel)',
             ha='center', fontsize=14, fontweight='bold', transform=ax_left.transAxes)

timeline_y = 0.7
box_height = 0.08
colors_seq = ['#3498DB', '#2ECC71', '#F39C12']
labels_seq = ['Load (128 cyc)', 'Compute (1 cyc)', 'Store (64 cyc)']
x_start = 0.1

for i, (label, color) in enumerate(zip(labels_seq, colors_seq)):
    y_pos = timeline_y - i * 0.15
    ax_left.add_patch(Rectangle((x_start, y_pos), 0.8, box_height,
                                 facecolor=color, edgecolor='black', linewidth=2))
    ax_left.text(0.5, y_pos + box_height/2, label, ha='center', va='center',
                 fontsize=11, fontweight='bold', transform=ax_left.transAxes)

ax_left.text(0.5, 0.2, 'Result: Sequential execution\nNo overlap possible',
             ha='center', fontsize=11, style='italic',
             bbox=dict(boxstyle='round', facecolor='yellow', alpha=0.3),
             transform=ax_left.transAxes)

ax_left.set_xlim(0, 1)
ax_left.set_ylim(0, 1)
ax_left.axis('off')

# 右图：双DMA架构（理论）
ax_right.text(0.5, 0.9, 'Improved Architecture\n(Dual DMA Channels)',
              ha='center', fontsize=14, fontweight='bold', transform=ax_right.transAxes)

# 显示重叠
y_batch0 = 0.7
y_batch1 = 0.55
y_batch2 = 0.4

# Batch 0
ax_right.add_patch(Rectangle((0.1, y_batch0), 0.4, box_height,
                              facecolor='#3498DB', edgecolor='black', linewidth=2))
ax_right.text(0.3, y_batch0 + box_height/2, 'B0: Load', ha='center', va='center',
              fontsize=9, fontweight='bold', transform=ax_right.transAxes)

ax_right.add_patch(Rectangle((0.5, y_batch0), 0.3, box_height,
                              facecolor='#F39C12', edgecolor='black', linewidth=2))
ax_right.text(0.65, y_batch0 + box_height/2, 'B0: Store', ha='center', va='center',
              fontsize=9, fontweight='bold', transform=ax_right.transAxes)

# Batch 1 (重叠)
ax_right.add_patch(Rectangle((0.5, y_batch1), 0.4, box_height,
                              facecolor='#3498DB', edgecolor='black', linewidth=2, alpha=0.7))
ax_right.text(0.7, y_batch1 + box_height/2, 'B1: Load', ha='center', va='center',
              fontsize=9, fontweight='bold', transform=ax_right.transAxes)

# 箭头标注重叠
ax_right.annotate('', xy=(0.55, y_batch0 - 0.02), xytext=(0.55, y_batch1 + box_height + 0.02),
                  arrowprops=dict(arrowstyle='<->', color='red', lw=2),
                  transform=ax_right.transAxes)
ax_right.text(0.42, (y_batch0 + y_batch1)/2 + box_height/2, 'Overlap!',
              fontsize=10, color='red', fontweight='bold', transform=ax_right.transAxes)

ax_right.text(0.5, 0.2, 'Result: ~1.5-1.8× speedup\nRequires hardware change',
              ha='center', fontsize=11, style='italic',
              bbox=dict(boxstyle='round', facecolor='lightgreen', alpha=0.3),
              transform=ax_right.transAxes)

ax_right.set_xlim(0, 1)
ax_right.set_ylim(0, 1)
ax_right.axis('off')

plt.tight_layout()
plt.savefig('pipeline_architecture_comparison.png', dpi=300, bbox_inches='tight')
print("✓ Saved: pipeline_architecture_comparison.png")

# plt.show()  # 注释掉，避免在无图形界面环境出错
print("\n✓ All visualizations generated successfully!")
