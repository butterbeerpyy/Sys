"""
Step 3: Visualize hardware output
Read selected indices and highlight on original image
"""

import matplotlib
matplotlib.use('Agg')  # 使用非交互式后端

import numpy as np
from PIL import Image, ImageDraw
import matplotlib.pyplot as plt
from pathlib import Path

def visualize_result(input_image_path, output_indices_file="output_indices.hex",
                     output_image="result_hardware.png", patch_size=8, grid_size=4):
    """
    可视化硬件输出结果

    Args:
        input_image_path: 原始输入图像
        output_indices_file: 硬件输出的索引文件
        output_image: 输出可视化图像
        patch_size: patch 大小
        grid_size: grid 大小
    """

    print("="*60)
    print("  Visualizing Hardware Results")
    print("="*60)

    # 读取原始图像
    img = Image.open(input_image_path).convert('RGB')
    img_size = patch_size * grid_size
    img = img.resize((img_size, img_size))

    # 读取硬件输出的索引
    if not Path(output_indices_file).exists():
        print(f"[ERROR] {output_indices_file} not found")
        return False

    with open(output_indices_file, 'r') as f:
        lines = f.readlines()
        selected_indices = [int(line.strip(), 16) for line in lines if line.strip()]

    print(f"\n[OK] Read {len(selected_indices)} selected indices")
    print(f"     Indices: {selected_indices}")

    # 创建可视化
    fig, axes = plt.subplots(1, 2, figsize=(12, 6))

    # 原图
    axes[0].imshow(img)
    axes[0].set_title(f"Original Image ({img_size}x{img_size})", fontsize=14, fontweight='bold')
    axes[0].axis('off')

    # 带高亮的图
    img_highlight = img.copy()
    draw = ImageDraw.Draw(img_highlight)

    max_patches = grid_size * grid_size

    for idx in selected_indices:
        if idx < max_patches:
            row = idx // grid_size
            col = idx % grid_size

            y = row * patch_size
            x = col * patch_size

            # 画绿框
            draw.rectangle([x, y, x+patch_size-1, y+patch_size-1],
                          outline='lime', width=2)

    axes[1].imshow(img_highlight)
    axes[1].set_title(f"Hardware Selected Regions\n(Top-{len(selected_indices)}, Green boxes)",
                     fontsize=14, fontweight='bold', color='green')
    axes[1].axis('off')

    plt.suptitle("Mini Pyramid Processor - Hardware Simulation Result",
                fontsize=16, fontweight='bold')
    plt.tight_layout()

    plt.savefig(output_image, dpi=150, bbox_inches='tight', facecolor='white')
    print(f"\n[OK] Saved visualization to: {output_image}")
    plt.close()

    return True

if __name__ == "__main__":
    import sys

    if len(sys.argv) > 1:
        input_img = sys.argv[1]
    else:
        if Path("test_pattern.png").exists():
            input_img = "test_pattern.png"
        elif Path("../real_images/dog.jpg").exists():
            input_img = "../real_images/dog.jpg"
        else:
            print("[ERROR] No input image found")
            sys.exit(1)

    # 默认参数
    output_idx = sys.argv[2] if len(sys.argv) > 2 else "output_indices.hex"
    output_img = sys.argv[3] if len(sys.argv) > 3 else "result_hardware.png"
    patch_size = int(sys.argv[4]) if len(sys.argv) > 4 else 8
    grid_size = int(sys.argv[5]) if len(sys.argv) > 5 else 4

    visualize_result(input_img, output_idx, output_img, patch_size, grid_size)
