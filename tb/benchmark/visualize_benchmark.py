#!/usr/bin/env python3
"""
visualize_benchmark.py
生成 CPU vs DMA 性能对比的科研级可视化图表
"""

import pandas as pd
import matplotlib.pyplot as plt
import numpy as np
from matplotlib.patches import Rectangle
import seaborn as sns

# 设置科研绘图风格
plt.rcParams['font.family'] = 'DejaVu Sans'
plt.rcParams['font.size'] = 11
plt.rcParams['axes.linewidth'] = 1.2
plt.rcParams['grid.alpha'] = 0.3
plt.rcParams['figure.dpi'] = 300

# 读取数据
df = pd.read_csv('benchmark_results.csv')

# 数据透视
df_pivot = df.pivot(index='workload', columns='mode', values='cycles')
df_pivot['speedup'] = df_pivot['CPU'] / df_pivot['DMA']

# 创建 2x2 子图
fig = plt.figure(figsize=(14, 10))
gs = fig.add_gridspec(2, 2, hspace=0.3, wspace=0.3)

# ==================== 子图 1: 绝对周期数对比 ====================
ax1 = fig.add_subplot(gs[0, :])

workloads = df_pivot.index
x = np.arange(len(workloads))
width = 0.35

bars1 = ax1.bar(x - width/2, df_pivot['CPU'], width, label='CPU Direct Write',
                color='#E74C3C', alpha=0.85, edgecolor='black', linewidth=1.2)
bars2 = ax1.bar(x + width/2, df_pivot['DMA'], width, label='DMA Mode',
                color='#3498DB', alpha=0.85, edgecolor='black', linewidth=1.2)

# 添加数值标签
for bar in bars1:
    height = bar.get_height()
    ax1.text(bar.get_x() + bar.get_width()/2., height,
             f'{int(height):,}',
             ha='center', va='bottom', fontsize=9, fontweight='bold')

for bar in bars2:
    height = bar.get_height()
    ax1.text(bar.get_x() + bar.get_width()/2., height,
             f'{int(height):,}',
             ha='center', va='bottom', fontsize=9, fontweight='bold')

ax1.set_ylabel('Execution Cycles', fontsize=13, fontweight='bold')
ax1.set_title('CPU Direct Write vs DMA Mode: Execution Cycles Comparison',
              fontsize=14, fontweight='bold', pad=15)
ax1.set_xticks(x)
ax1.set_xticklabels(workloads, rotation=25, ha='right')
ax1.legend(loc='upper left', frameon=True, shadow=True, fontsize=11)
ax1.grid(axis='y', alpha=0.3, linestyle='--')
ax1.set_axisbelow(True)

# ==================== 子图 2: 加速比 ====================
ax2 = fig.add_subplot(gs[1, 0])

colors = ['#27AE60' if s > 1 else '#E67E22' for s in df_pivot['speedup']]
bars = ax2.barh(workloads, df_pivot['speedup'], color=colors, alpha=0.85,
                edgecolor='black', linewidth=1.2)

# 添加数值标签
for i, (bar, val) in enumerate(zip(bars, df_pivot['speedup'])):
    ax2.text(val + 0.05, bar.get_y() + bar.get_height()/2,
             f'{val:.2f}×',
             va='center', fontsize=10, fontweight='bold')

# 添加基准线
ax2.axvline(x=1, color='red', linestyle='--', linewidth=2, label='Baseline (1×)')

ax2.set_xlabel('Speedup (CPU / DMA)', fontsize=12, fontweight='bold')
ax2.set_title('DMA Speedup over CPU Direct Write',
              fontsize=13, fontweight='bold', pad=12)
ax2.legend(loc='lower right', frameon=True, shadow=True)
ax2.grid(axis='x', alpha=0.3, linestyle='--')
ax2.set_axisbelow(True)

# ==================== 子图 3: 分类对比（VMAC vs VLM）====================
ax3 = fig.add_subplot(gs[1, 1])

# 分类统计
vmac_data = df[df['workload'].str.contains('VMAC')]
vlm_data = df[df['workload'].str.contains('VLM')]

categories = ['VMAC\nMatrix Ops', 'VLM\nImage Proc']
cpu_avg = [vmac_data[vmac_data['mode']=='CPU']['cycles'].mean(),
           vlm_data[vlm_data['mode']=='CPU']['cycles'].mean()]
dma_avg = [vmac_data[vmac_data['mode']=='DMA']['cycles'].mean(),
           vlm_data[vlm_data['mode']=='DMA']['cycles'].mean()]

x_cat = np.arange(len(categories))
width = 0.35

bars1 = ax3.bar(x_cat - width/2, cpu_avg, width, label='CPU Avg',
                color='#E74C3C', alpha=0.85, edgecolor='black', linewidth=1.2)
bars2 = ax3.bar(x_cat + width/2, dma_avg, width, label='DMA Avg',
                color='#3498DB', alpha=0.85, edgecolor='black', linewidth=1.2)

# 添加数值标签
for bar in bars1:
    height = bar.get_height()
    ax3.text(bar.get_x() + bar.get_width()/2., height,
             f'{int(height):,}',
             ha='center', va='bottom', fontsize=10, fontweight='bold')

for bar in bars2:
    height = bar.get_height()
    ax3.text(bar.get_x() + bar.get_width()/2., height,
             f'{int(height):,}',
             ha='center', va='bottom', fontsize=10, fontweight='bold')

ax3.set_ylabel('Average Cycles', fontsize=12, fontweight='bold')
ax3.set_title('Average Performance by Workload Type',
              fontsize=13, fontweight='bold', pad=12)
ax3.set_xticks(x_cat)
ax3.set_xticklabels(categories, fontsize=11)
ax3.legend(loc='upper left', frameon=True, shadow=True)
ax3.grid(axis='y', alpha=0.3, linestyle='--')
ax3.set_axisbelow(True)

# ==================== 总标题和注释 ====================
fig.suptitle('Hardware Accelerator Performance Benchmark:\nCPU Direct Write vs DMA Transfer',
             fontsize=16, fontweight='bold', y=0.98)

# 添加统计信息文本框
stats_text = f"""
Key Statistics:
• Total Tests: {len(df)//2}
• Avg Speedup: {df_pivot['speedup'].mean():.2f}×
• Max Speedup: {df_pivot['speedup'].max():.2f}×
• Min Speedup: {df_pivot['speedup'].min():.2f}×
"""

fig.text(0.02, 0.02, stats_text, fontsize=10,
         bbox=dict(boxstyle='round', facecolor='wheat', alpha=0.3),
         verticalalignment='bottom', family='monospace')

# 保存
plt.savefig('benchmark_comparison.png', dpi=300, bbox_inches='tight')
plt.savefig('benchmark_comparison.pdf', bbox_inches='tight')
print("✓ Saved: benchmark_comparison.png")
print("✓ Saved: benchmark_comparison.pdf")

# ==================== 额外图：热力图 ====================
fig2, ax = plt.subplots(figsize=(10, 6))

# 准备热力图数据
heatmap_data = df.pivot_table(index='workload', columns='mode', values='cycles')

# 归一化（以 CPU 为基准）
heatmap_norm = heatmap_data.div(heatmap_data['CPU'], axis=0)

sns.heatmap(heatmap_norm, annot=True, fmt='.2f', cmap='RdYlGn_r',
            cbar_kws={'label': 'Normalized Cycles (CPU=1.0)'},
            linewidths=2, linecolor='black', ax=ax)

ax.set_title('Normalized Performance Heatmap\n(Lower is Better)',
             fontsize=14, fontweight='bold', pad=15)
ax.set_xlabel('Execution Mode', fontsize=12, fontweight='bold')
ax.set_ylabel('Workload', fontsize=12, fontweight='bold')

plt.tight_layout()
plt.savefig('benchmark_heatmap.png', dpi=300, bbox_inches='tight')
print("✓ Saved: benchmark_heatmap.png")

# ==================== 第三张图：数据传输效率 ====================
fig3, ax = plt.subplots(figsize=(10, 6))

# 估算数据量
data_size = {
    'VMAC_2D_4x4': 4*4*2*4,      # A + B (bytes)
    'VMAC_2D_8x8': 8*8*2*4,
    'VMAC_3D_batch2_4x4': 4*4*2*4*2,
    'VMAC_3D_batch4_8x8': 8*8*2*4*4,
    'VLM_112x112': 112*112
}

df['data_bytes'] = df['workload'].map(data_size)
df['throughput'] = df['data_bytes'] / df['cycles']  # bytes/cycle

df_throughput = df.pivot(index='workload', columns='mode', values='throughput')

x = np.arange(len(workloads))
bars1 = ax.bar(x - width/2, df_throughput['CPU'], width, label='CPU',
               color='#E74C3C', alpha=0.85, edgecolor='black', linewidth=1.2)
bars2 = ax.bar(x + width/2, df_throughput['DMA'], width, label='DMA',
               color='#3498DB', alpha=0.85, edgecolor='black', linewidth=1.2)

ax.set_ylabel('Throughput (Bytes/Cycle)', fontsize=12, fontweight='bold')
ax.set_title('Data Transfer Throughput Comparison',
             fontsize=14, fontweight='bold', pad=15)
ax.set_xticks(x)
ax.set_xticklabels(workloads, rotation=25, ha='right')
ax.legend(loc='upper left', frameon=True, shadow=True)
ax.grid(axis='y', alpha=0.3, linestyle='--')
ax.set_axisbelow(True)

# 添加数值标签
for bar in bars1:
    height = bar.get_height()
    if height > 0:
        ax.text(bar.get_x() + bar.get_width()/2., height,
                f'{height:.3f}',
                ha='center', va='bottom', fontsize=9, fontweight='bold')

for bar in bars2:
    height = bar.get_height()
    if height > 0:
        ax.text(bar.get_x() + bar.get_width()/2., height,
                f'{height:.3f}',
                ha='center', va='bottom', fontsize=9, fontweight='bold')

plt.tight_layout()
plt.savefig('benchmark_throughput.png', dpi=300, bbox_inches='tight')
print("✓ Saved: benchmark_throughput.png")

plt.show()
print("\n✓ All visualizations generated successfully!")
