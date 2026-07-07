#!/usr/bin/env python3
"""
compare_single_vs_dual_dma.py
对比单 DMA 和双 DMA 的性能
"""

import pandas as pd
import matplotlib.pyplot as plt
import numpy as np

# 设置绘图风格
plt.rcParams['font.family'] = 'DejaVu Sans'
plt.rcParams['font.size'] = 11
plt.rcParams['figure.dpi'] = 300

# 单 DMA 数据（从之前的测试）
single_dma = {
    'batch': [1, 2, 4, 8],
    'cycles': [200, 396, 788, 1572]
}

# 双 DMA 数据（刚刚测试）
dual_dma = {
    'batch': [1, 2, 4, 8],
    'cycles': [203, 336, 602, 1134]
}

# 创建 DataFrame
df_single = pd.DataFrame(single_dma)
df_dual = pd.DataFrame(dual_dma)

# 计算加速比
df_dual['speedup'] = df_single['cycles'] / df_dual['cycles']

print("=" * 60)
print("单 DMA vs 双 DMA 性能对比")
print("=" * 60)
print("\n详细数据:")
print(f"{'Batch':<8} {'单DMA':<12} {'双DMA':<12} {'加速比':<12}")
print("-" * 60)
for i in range(len(df_single)):
    batch = df_single['batch'].iloc[i]
    single = df_single['cycles'].iloc[i]
    dual = df_dual['cycles'].iloc[i]
    speedup = df_dual['speedup'].iloc[i]
    print(f"{batch:<8} {single:<12} {dual:<12} {speedup:.3f}×")

print("\n关键发现:")
print(f"  • Batch=1: {df_dual['speedup'].iloc[0]:.3f}× (无重叠机会)")
print(f"  • Batch=2: {df_dual['speedup'].iloc[1]:.3f}× (开始体现优势)")
print(f"  • Batch=4: {df_dual['speedup'].iloc[2]:.3f}× (明显优势)")
print(f"  • Batch=8: {df_dual['speedup'].iloc[3]:.3f}× (稳定状态)")
print(f"\n平均加速比: {df_dual['speedup'].mean():.3f}×")
print("=" * 60)

# 创建可视化
fig, axes = plt.subplots(2, 2, figsize=(14, 10))
fig.suptitle('Single DMA vs Dual DMA Performance Comparison',
             fontsize=16, fontweight='bold', y=0.98)

# ========== 子图 1: 绝对周期数对比 ==========
ax1 = axes[0, 0]
x = np.arange(len(df_single))
width = 0.35

bars1 = ax1.bar(x - width/2, df_single['cycles'], width,
                label='Single DMA', color='#E74C3C', alpha=0.85,
                edgecolor='black', linewidth=1.2)
bars2 = ax1.bar(x + width/2, df_dual['cycles'], width,
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

ax1.set_ylabel('Execution Cycles', fontsize=12, fontweight='bold')
ax1.set_title('Absolute Cycles Comparison', fontsize=13, fontweight='bold', pad=12)
ax1.set_xticks(x)
ax1.set_xticklabels([f'Batch={b}' for b in df_single['batch']])
ax1.legend(loc='upper left', frameon=True, shadow=True)
ax1.grid(axis='y', alpha=0.3, linestyle='--')
ax1.set_axisbelow(True)

# ========== 子图 2: 加速比 ==========
ax2 = axes[0, 1]
colors = ['#95A5A6' if s < 1.05 else '#27AE60' if s < 1.3 else '#F39C12'
          for s in df_dual['speedup']]
bars = ax2.bar(df_dual['batch'], df_dual['speedup'],
               color=colors, alpha=0.85, edgecolor='black', linewidth=1.2)

# 添加数值标签
for bar, val in zip(bars, df_dual['speedup']):
    height = bar.get_height()
    ax2.text(bar.get_x() + bar.get_width()/2., height,
             f'{val:.3f}×', ha='center', va='bottom',
             fontsize=10, fontweight='bold')

ax2.axhline(y=1.0, color='red', linestyle='--', linewidth=2,
            alpha=0.7, label='Baseline (1.0×)')
ax2.set_xlabel('Batch Count', fontsize=12, fontweight='bold')
ax2.set_ylabel('Speedup (Single / Dual)', fontsize=12, fontweight='bold')
ax2.set_title('Dual DMA Speedup', fontsize=13, fontweight='bold', pad=12)
ax2.legend(loc='upper left', frameon=True, shadow=True)
ax2.grid(alpha=0.3, linestyle='--')
ax2.set_axisbelow(True)
ax2.set_ylim([0.9, max(df_dual['speedup']) * 1.1])

# ========== 子图 3: 周期数减少 ==========
ax3 = axes[1, 0]
cycles_saved = df_single['cycles'] - df_dual['cycles']
percentage_saved = (cycles_saved / df_single['cycles']) * 100

bars = ax3.bar(df_dual['batch'], cycles_saved,
               color='#2ECC71', alpha=0.85, edgecolor='black', linewidth=1.2)

# 添加数值标签
for bar, val, pct in zip(bars, cycles_saved, percentage_saved):
    height = bar.get_height()
    ax3.text(bar.get_x() + bar.get_width()/2., height,
             f'{int(val)}\n({pct:.1f}%)', ha='center', va='bottom',
             fontsize=9, fontweight='bold')

ax3.set_xlabel('Batch Count', fontsize=12, fontweight='bold')
ax3.set_ylabel('Cycles Saved', fontsize=12, fontweight='bold')
ax3.set_title('Performance Improvement', fontsize=13, fontweight='bold', pad=12)
ax3.grid(axis='y', alpha=0.3, linestyle='--')
ax3.set_axisbelow(True)

# ========== 子图 4: 效率分析 ==========
ax4 = axes[1, 1]

# 计算每 batch 的平均周期
single_per_batch = df_single['cycles'] / df_single['batch']
dual_per_batch = df_dual['cycles'] / df_dual['batch']

x = np.arange(len(df_single))
width = 0.35

bars1 = ax4.bar(x - width/2, single_per_batch, width,
                label='Single DMA', color='#E74C3C', alpha=0.85,
                edgecolor='black', linewidth=1.2)
bars2 = ax4.bar(x + width/2, dual_per_batch, width,
                label='Dual DMA', color='#3498DB', alpha=0.85,
                edgecolor='black', linewidth=1.2)

# 添加数值标签
for bar in bars1:
    height = bar.get_height()
    ax4.text(bar.get_x() + bar.get_width()/2., height,
             f'{int(height)}', ha='center', va='bottom',
             fontsize=9, fontweight='bold')

for bar in bars2:
    height = bar.get_height()
    ax4.text(bar.get_x() + bar.get_width()/2., height,
             f'{int(height)}', ha='center', va='bottom',
             fontsize=9, fontweight='bold')

ax4.set_ylabel('Cycles per Batch', fontsize=12, fontweight='bold')
ax4.set_title('Efficiency: Cycles per Batch', fontsize=13, fontweight='bold', pad=12)
ax4.set_xticks(x)
ax4.set_xticklabels([f'Batch={b}' for b in df_single['batch']])
ax4.legend(loc='upper right', frameon=True, shadow=True)
ax4.grid(axis='y', alpha=0.3, linestyle='--')
ax4.set_axisbelow(True)

# 添加关键发现文本框
findings_text = f"""
关键发现:
• Batch=1: {df_dual['speedup'].iloc[0]:.2f}× (基准)
• Batch=2: {df_dual['speedup'].iloc[1]:.2f}× (开始优化)
• Batch=4: {df_dual['speedup'].iloc[2]:.2f}× (明显提升)
• Batch=8: {df_dual['speedup'].iloc[3]:.2f}× (稳定)

平均加速: {df_dual['speedup'].mean():.2f}×
周期节省: {percentage_saved.mean():.1f}%

结论: 双DMA在多batch场景下
显著提升性能!
"""

fig.text(0.02, 0.02, findings_text, fontsize=10,
         bbox=dict(boxstyle='round', facecolor='#E8F8F5',
                   alpha=0.9, edgecolor='#27AE60', linewidth=2),
         verticalalignment='bottom', family='monospace')

plt.tight_layout()
plt.savefig('tb/benchmark/single_vs_dual_dma.png', dpi=300, bbox_inches='tight')
plt.savefig('tb/benchmark/single_vs_dual_dma.pdf', bbox_inches='tight')
print("\n✓ 保存图表: tb/benchmark/single_vs_dual_dma.png")
print("✓ 保存图表: tb/benchmark/single_vs_dual_dma.pdf")
