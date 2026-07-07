#!/usr/bin/env python3
"""
visualize_single_vs_dual.py
单 DMA vs 双 DMA 完整可视化
"""

import matplotlib
matplotlib.use('Agg')  # 使用非交互式后端，避免 Qt 错误

import pandas as pd
import matplotlib.pyplot as plt
import numpy as np

# 设置科研绘图风格
plt.rcParams['font.family'] = 'DejaVu Sans'
plt.rcParams['font.size'] = 11
plt.rcParams['axes.linewidth'] = 1.2
plt.rcParams['grid.alpha'] = 0.3
plt.rcParams['figure.dpi'] = 300

# 读取数据
df = pd.read_csv('single_vs_dual_results.csv')

print("=" * 70)
print("单 DMA vs 双 DMA 性能对比")
print("=" * 70)
print("\n原始数据:")
print(df.to_string(index=False))

print("\n关键统计:")
print(f"  平均加速比: {df['speedup'].mean():.3f}×")
print(f"  最大加速比: {df['speedup'].max():.3f}× (Batch={df.loc[df['speedup'].idxmax(), 'batch']})")
print(f"  平均性能提升: {df['improvement_pct'].mean():.1f}%")
print("=" * 70)

# 创建 2×3 子图
fig = plt.figure(figsize=(18, 12))
gs = fig.add_gridspec(3, 3, hspace=0.35, wspace=0.3)

# ========== 子图 1: 绝对周期数对比 (柱状图) ==========
ax1 = fig.add_subplot(gs[0, :2])

x = np.arange(len(df))
width = 0.35

bars1 = ax1.bar(x - width/2, df['single_cycles'], width,
                label='Single DMA', color='#E74C3C', alpha=0.85,
                edgecolor='black', linewidth=1.2)
bars2 = ax1.bar(x + width/2, df['dual_cycles'], width,
                label='Dual DMA', color='#3498DB', alpha=0.85,
                edgecolor='black', linewidth=1.2)

# 添加数值标签
for bar in bars1:
    height = bar.get_height()
    ax1.text(bar.get_x() + bar.get_width()/2., height,
             f'{int(height)}', ha='center', va='bottom',
             fontsize=9, fontweight='bold')

for bar in bars2:
    height = bar.get_height()
    ax1.text(bar.get_x() + bar.get_width()/2., height,
             f'{int(height)}', ha='center', va='bottom',
             fontsize=9, fontweight='bold')

ax1.set_ylabel('Execution Cycles', fontsize=13, fontweight='bold')
ax1.set_title('Absolute Execution Cycles Comparison',
              fontsize=14, fontweight='bold', pad=15)
ax1.set_xticks(x)
ax1.set_xticklabels([f'Batch={b}' for b in df['batch']])
ax1.legend(loc='upper left', frameon=True, shadow=True, fontsize=11)
ax1.grid(axis='y', alpha=0.3, linestyle='--')
ax1.set_axisbelow(True)

# ========== 子图 2: 加速比 (柱状图) ==========
ax2 = fig.add_subplot(gs[0, 2])

colors = ['#95A5A6' if s <= 1.0 else
          '#27AE60' if s <= 1.2 else
          '#F39C12' if s <= 1.4 else '#E74C3C'
          for s in df['speedup']]

bars = ax2.bar(df['batch'], df['speedup'], color=colors,
               alpha=0.85, edgecolor='black', linewidth=1.2)

# 添加数值标签
for bar, val in zip(bars, df['speedup']):
    height = bar.get_height()
    ax2.text(bar.get_x() + bar.get_width()/2., height,
             f'{val:.2f}×', ha='center', va='bottom',
             fontsize=9, fontweight='bold')

ax2.axhline(y=1.0, color='red', linestyle='--', linewidth=2,
            alpha=0.7, label='Baseline')
ax2.set_xlabel('Batch Count', fontsize=12, fontweight='bold')
ax2.set_ylabel('Speedup', fontsize=12, fontweight='bold')
ax2.set_title('Dual DMA Speedup', fontsize=13, fontweight='bold', pad=12)
ax2.legend(loc='upper left', frameon=True, shadow=True, fontsize=10)
ax2.grid(alpha=0.3, linestyle='--')
ax2.set_axisbelow(True)
ax2.set_ylim([0.8, max(df['speedup']) * 1.15])

# ========== 子图 3: 周期数变化趋势 (折线图) ==========
ax3 = fig.add_subplot(gs[1, :2])

ax3.plot(df['batch'], df['single_cycles'], 'o-', linewidth=2.5,
         markersize=10, label='Single DMA', color='#E74C3C', alpha=0.8)
ax3.plot(df['batch'], df['dual_cycles'], 's-', linewidth=2.5,
         markersize=10, label='Dual DMA', color='#3498DB', alpha=0.8)

# 填充区域
ax3.fill_between(df['batch'], df['single_cycles'], df['dual_cycles'],
                 alpha=0.2, color='#2ECC71', label='Performance Gain')

ax3.set_xlabel('Batch Count', fontsize=13, fontweight='bold')
ax3.set_ylabel('Execution Cycles', fontsize=13, fontweight='bold')
ax3.set_title('Performance Scaling with Batch Size',
              fontsize=14, fontweight='bold', pad=15)
ax3.legend(loc='upper left', frameon=True, shadow=True, fontsize=11)
ax3.grid(alpha=0.3, linestyle='--')
ax3.set_axisbelow(True)

# ========== 子图 4: 性能提升百分比 ==========
ax4 = fig.add_subplot(gs[1, 2])

colors_pct = ['#27AE60' if p > 0 else '#E74C3C' for p in df['improvement_pct']]
bars = ax4.barh(df['batch'], df['improvement_pct'], color=colors_pct,
                alpha=0.85, edgecolor='black', linewidth=1.2)

# 添加数值标签
for bar, val in zip(bars, df['improvement_pct']):
    width = bar.get_width()
    ax4.text(width + 1, bar.get_y() + bar.get_height()/2.,
             f'{val:.1f}%', va='center', fontsize=10, fontweight='bold')

ax4.axvline(x=0, color='black', linestyle='-', linewidth=1.5)
ax4.set_xlabel('Improvement (%)', fontsize=12, fontweight='bold')
ax4.set_ylabel('Batch Count', fontsize=12, fontweight='bold')
ax4.set_title('Performance Improvement', fontsize=13, fontweight='bold', pad=12)
ax4.grid(axis='x', alpha=0.3, linestyle='--')
ax4.set_axisbelow(True)

# ========== 子图 5: 每 Batch 平均周期 ==========
ax5 = fig.add_subplot(gs[2, :2])

single_per_batch = df['single_cycles'] / df['batch']
dual_per_batch = df['dual_cycles'] / df['batch']

x = np.arange(len(df))
width = 0.35

bars1 = ax5.bar(x - width/2, single_per_batch, width,
                label='Single DMA', color='#E74C3C', alpha=0.85,
                edgecolor='black', linewidth=1.2)
bars2 = ax5.bar(x + width/2, dual_per_batch, width,
                label='Dual DMA', color='#3498DB', alpha=0.85,
                edgecolor='black', linewidth=1.2)

# 添加数值标签
for bar in bars1:
    height = bar.get_height()
    ax5.text(bar.get_x() + bar.get_width()/2., height,
             f'{int(height)}', ha='center', va='bottom',
             fontsize=9, fontweight='bold')

for bar in bars2:
    height = bar.get_height()
    ax5.text(bar.get_x() + bar.get_width()/2., height,
             f'{int(height)}', ha='center', va='bottom',
             fontsize=9, fontweight='bold')

ax5.set_ylabel('Cycles per Batch', fontsize=13, fontweight='bold')
ax5.set_title('Efficiency: Average Cycles per Batch',
              fontsize=14, fontweight='bold', pad=15)
ax5.set_xticks(x)
ax5.set_xticklabels([f'Batch={b}' for b in df['batch']])
ax5.legend(loc='upper right', frameon=True, shadow=True, fontsize=11)
ax5.grid(axis='y', alpha=0.3, linestyle='--')
ax5.set_axisbelow(True)

# ========== 子图 6: 架构对比图 ==========
ax6 = fig.add_subplot(gs[2, 2])
ax6.axis('off')

# 单 DMA 架构
y_start = 0.75
ax6.text(0.5, y_start, 'Single DMA Architecture',
         ha='center', fontsize=11, fontweight='bold',
         transform=ax6.transAxes)

y_start -= 0.15
ax6.add_patch(plt.Rectangle((0.1, y_start - 0.05), 0.8, 0.08,
                             facecolor='#E74C3C', edgecolor='black',
                             linewidth=2, transform=ax6.transAxes))
ax6.text(0.5, y_start, 'Single Channel',
         ha='center', va='center', fontsize=10, fontweight='bold',
         transform=ax6.transAxes)

y_start -= 0.1
ax6.text(0.5, y_start, 'Read/Write: Serial',
         ha='center', fontsize=9, style='italic',
         transform=ax6.transAxes)

# 双 DMA 架构
y_start -= 0.2
ax6.text(0.5, y_start, 'Dual DMA Architecture',
         ha='center', fontsize=11, fontweight='bold',
         transform=ax6.transAxes)

y_start -= 0.15
ax6.add_patch(plt.Rectangle((0.1, y_start - 0.05), 0.8, 0.08,
                             facecolor='#3498DB', edgecolor='black',
                             linewidth=2, transform=ax6.transAxes))
ax6.text(0.5, y_start, 'Read Channel',
         ha='center', va='center', fontsize=10, fontweight='bold',
         color='white', transform=ax6.transAxes)

y_start -= 0.12
ax6.add_patch(plt.Rectangle((0.1, y_start - 0.05), 0.8, 0.08,
                             facecolor='#3498DB', edgecolor='black',
                             linewidth=2, transform=ax6.transAxes))
ax6.text(0.5, y_start, 'Write Channel',
         ha='center', va='center', fontsize=10, fontweight='bold',
         color='white', transform=ax6.transAxes)

y_start -= 0.1
ax6.text(0.5, y_start, 'Read/Write: Parallel ✓',
         ha='center', fontsize=9, style='italic',
         color='#27AE60', fontweight='bold',
         transform=ax6.transAxes)

# 总标题
fig.suptitle('Single DMA vs Dual DMA: Comprehensive Performance Analysis',
             fontsize=16, fontweight='bold', y=0.98)

# 添加关键发现文本框
findings_text = f"""
Key Findings:
• Average Speedup: {df['speedup'].mean():.2f}×
• Max Speedup: {df['speedup'].max():.2f}× (Batch={df.loc[df['speedup'].idxmax(), 'batch']})
• Avg Improvement: {df['improvement_pct'].mean():.1f}%

Dual DMA Benefits:
✓ Independent Read/Write
✓ Better scaling with batches
✓ ~{int((df['speedup'].mean() - 1) * 100)}% faster on average
"""

fig.text(0.02, 0.02, findings_text, fontsize=10,
         bbox=dict(boxstyle='round', facecolor='#E8F8F5',
                   alpha=0.9, edgecolor='#27AE60', linewidth=2),
         verticalalignment='bottom', family='monospace')

plt.tight_layout()

# 保存图表
plt.savefig('single_vs_dual_comparison.png', dpi=300, bbox_inches='tight')
plt.savefig('single_vs_dual_comparison.pdf', bbox_inches='tight')
print("\n✓ 保存图表: single_vs_dual_comparison.png")
print("✓ 保存图表: single_vs_dual_comparison.pdf")

# 生成详细报告
report = f"""
# Single DMA vs Dual DMA Performance Report

## Test Summary

Total Tests: {len(df)}
Batch Range: {df['batch'].min()} - {df['batch'].max()}

## Performance Metrics

| Batch | Single DMA | Dual DMA | Saved Cycles | Speedup | Improvement |
|-------|-----------|----------|--------------|---------|-------------|
"""

for _, row in df.iterrows():
    saved = row['single_cycles'] - row['dual_cycles']
    report += f"| {int(row['batch'])} | {int(row['single_cycles'])} | {int(row['dual_cycles'])} | {int(saved)} | {row['speedup']:.3f}× | {row['improvement_pct']:.1f}% |\n"

report += f"""
## Key Statistics

- **Average Speedup**: {df['speedup'].mean():.3f}×
- **Maximum Speedup**: {df['speedup'].max():.3f}× (Batch={df.loc[df['speedup'].idxmax(), 'batch']})
- **Minimum Speedup**: {df['speedup'].min():.3f}× (Batch={df.loc[df['speedup'].idxmin(), 'batch']})
- **Average Improvement**: {df['improvement_pct'].mean():.1f}%

## Conclusion

Dual DMA architecture shows consistent performance improvement across all batch sizes,
with an average speedup of {df['speedup'].mean():.2f}× compared to single DMA.
The benefit increases with larger batch sizes, demonstrating effective overlap of
read and write operations.
"""

with open('single_vs_dual_report.md', 'w') as f:
    f.write(report)

print("✓ 生成报告: single_vs_dual_report.md")
print("\n✓ 所有输出完成！")
