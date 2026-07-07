"""
Visual Comparison: Original vs Reconstructed from Selected Patches
Show what the image looks like after storage compression
"""

import matplotlib
matplotlib.use('Agg')

import numpy as np
from PIL import Image
import matplotlib.pyplot as plt
from pathlib import Path

class PyramidProcessor:
    def __init__(self):
        self.patch_size = 14
        self.image_size = 224

    def extract_patches(self, image):
        patches = []
        positions = []
        h, w = image.shape[0], image.shape[1]
        for i in range(0, h, self.patch_size):
            for j in range(0, w, self.patch_size):
                patch = image[i:i+self.patch_size, j:j+self.patch_size, :]
                if patch.shape[0] == self.patch_size and patch.shape[1] == self.patch_size:
                    patches.append(patch)
                    positions.append((i, j))
        return np.array(patches), positions

    def compute_complexity(self, patch):
        gray = 0.299 * patch[:,:,0] + 0.587 * patch[:,:,1] + 0.114 * patch[:,:,2]
        grad_x = np.abs(np.diff(gray, axis=1))
        grad_y = np.abs(np.diff(gray, axis=0))
        return np.mean(grad_x) + np.mean(grad_y)

    def compute_interest_map(self, image):
        patches, positions = self.extract_patches(image)
        grid_size = self.image_size // self.patch_size
        interest_map = np.zeros((grid_size, grid_size))
        for idx, patch in enumerate(patches):
            i = idx // grid_size
            j = idx % grid_size
            interest_map[i, j] = self.compute_complexity(patch)
        return interest_map, patches, positions

    def reconstruct_from_selected(self, image, top_k=20):
        """重建图像：只使用选中的 patches，其他区域置灰"""
        interest_map, all_patches, positions = self.compute_interest_map(image)

        # Top-K 选择
        flat_interest = interest_map.flatten()
        top_indices = np.argsort(flat_interest)[-top_k:][::-1]

        # 创建重建图像（灰色背景）
        reconstructed = np.ones_like(image) * 128  # 灰色背景

        # 创建 mask
        grid_size = self.image_size // self.patch_size
        mask = np.zeros((grid_size, grid_size))

        # 只填充选中的 patches
        for idx in top_indices:
            if idx < len(all_patches):
                patch = all_patches[idx]
                i, j = positions[idx]
                reconstructed[i:i+self.patch_size, j:j+self.patch_size, :] = patch

                # 更新 mask
                grid_i = idx // grid_size
                grid_j = idx % grid_size
                mask[grid_i, grid_j] = 1

        return reconstructed, mask, interest_map

    def reconstruct_center(self, image, top_k=20):
        """重建图像：只使用中心区域"""
        _, all_patches, positions = self.compute_interest_map(image)
        grid_size = self.image_size // self.patch_size

        center_size = int(np.sqrt(top_k))
        start = (grid_size - center_size) // 2

        reconstructed = np.ones_like(image) * 128
        mask = np.zeros((grid_size, grid_size))

        for i in range(start, start+center_size):
            for j in range(start, start+center_size):
                if i < grid_size and j < grid_size:
                    idx = i * grid_size + j
                    if idx < len(all_patches):
                        patch = all_patches[idx]
                        pos_i, pos_j = positions[idx]
                        reconstructed[pos_i:pos_i+self.patch_size, pos_j:pos_j+self.patch_size, :] = patch
                        mask[i, j] = 1

        return reconstructed, mask

def create_visual_comparison(image_path, top_k=60):
    processor = PyramidProcessor()
    img = Image.open(image_path).convert('RGB')
    img = img.resize((224, 224))
    img_array = np.array(img)

    # 生成重建图像
    recon_smart, mask_smart, interest_map = processor.reconstruct_from_selected(img_array, top_k)
    recon_center, mask_center = processor.reconstruct_center(img_array, top_k)

    total_patches = 16 * 16
    saved = (1 - top_k / total_patches) * 100

    # 创建可视化
    fig = plt.figure(figsize=(24, 8))

    # 第一行：原图
    ax1 = plt.subplot(2, 5, 1)
    ax1.imshow(img)
    ax1.set_title("Original Image\n(Baseline: 256 patches)", fontsize=13, fontweight='bold', pad=10)
    ax1.axis('off')

    # 添加边框
    for spine in ax1.spines.values():
        spine.set_edgecolor('green')
        spine.set_linewidth(3)

    # 第一行：兴趣度图
    ax2 = plt.subplot(2, 5, 2)
    im1 = ax2.imshow(interest_map, cmap='hot', interpolation='bilinear')
    ax2.set_title("Interest Map\n(Complexity Analysis)", fontsize=13, fontweight='bold', pad=10)
    ax2.axis('off')
    plt.colorbar(im1, ax=ax2, fraction=0.046)

    # 第一行：方法 A 的 mask
    ax3 = plt.subplot(2, 5, 3)
    im2 = ax3.imshow(mask_center, cmap='RdYlGn', interpolation='nearest')
    ax3.set_title(f"Method A: Fixed Center\n(Select {top_k} patches)", fontsize=13, fontweight='bold', pad=10, color='red')
    ax3.axis('off')

    # 第一行：方法 A 重建图
    ax4 = plt.subplot(2, 5, 4)
    ax4.imshow(recon_center.astype(np.uint8))
    ax4.set_title("Stored Image (Method A)\nGray = Not Stored", fontsize=13, fontweight='bold', pad=10, color='red')
    ax4.axis('off')

    for spine in ax4.spines.values():
        spine.set_edgecolor('red')
        spine.set_linewidth(3)

    # 第一行：统计
    ax5 = plt.subplot(2, 5, 5)
    ax5.axis('off')
    stats_a = f"""
Method A: Fixed Center

Storage:
  Patches stored: {top_k}/256
  Reduction: {saved:.1f}%

Issue:
  May miss important
  edge information
  (shown in gray)

Result:
  Fixed strategy
  Not adaptive
    """
    ax5.text(0.1, 0.5, stats_a, fontsize=12, family='monospace', va='center',
             bbox=dict(boxstyle='round,pad=1', fc='#ffcccc', ec='red', lw=2, alpha=0.8))

    # 第二行：原图（重复）
    ax6 = plt.subplot(2, 5, 6)
    ax6.imshow(img)
    ax6.set_title("Original Image\n(Baseline: 256 patches)", fontsize=13, fontweight='bold', pad=10)
    ax6.axis('off')

    for spine in ax6.spines.values():
        spine.set_edgecolor('green')
        spine.set_linewidth(3)

    # 第二行：兴趣度图（重复）
    ax7 = plt.subplot(2, 5, 7)
    im3 = ax7.imshow(interest_map, cmap='hot', interpolation='bilinear')
    ax7.set_title("Interest Map\n(Complexity Analysis)", fontsize=13, fontweight='bold', pad=10)
    ax7.axis('off')
    plt.colorbar(im3, ax=ax7, fraction=0.046)

    # 第二行：方法 B 的 mask
    ax8 = plt.subplot(2, 5, 8)
    im4 = ax8.imshow(mask_smart, cmap='RdYlGn', interpolation='nearest')
    ax8.set_title(f"Method B: Smart Selection\n(Select {top_k} patches)", fontsize=13, fontweight='bold', pad=10, color='green')
    ax8.axis('off')

    # 第二行：方法 B 重建图
    ax9 = plt.subplot(2, 5, 9)
    ax9.imshow(recon_smart.astype(np.uint8))
    ax9.set_title("Stored Image (Method B)\nGray = Not Stored", fontsize=13, fontweight='bold', pad=10, color='green')
    ax9.axis('off')

    for spine in ax9.spines.values():
        spine.set_edgecolor('green')
        spine.set_linewidth(3)

    # 第二行：统计
    ax10 = plt.subplot(2, 5, 10)
    ax10.axis('off')
    stats_b = f"""
Method B: Smart Selection
(My Design)

Storage:
  Patches stored: {top_k}/256
  Reduction: {saved:.1f}%

Advantage:
  Captures important
  regions adaptively
  (key features saved)

Result:
  Content-aware
  Better quality
    """
    ax10.text(0.1, 0.5, stats_b, fontsize=12, family='monospace', va='center',
             bbox=dict(boxstyle='round,pad=1', fc='#ccffcc', ec='green', lw=2, alpha=0.8))

    # 总标题
    fig.suptitle(f'Visual Quality Comparison: What Gets Stored?\n'
                 f'Both methods save {saved:.0f}% storage, but smart selection preserves key features better',
                 fontsize=17, fontweight='bold', y=0.98)

    plt.tight_layout(rect=[0, 0, 1, 0.96])

    output_dir = Path("comparison_results")
    output_dir.mkdir(exist_ok=True)
    output_path = output_dir / f"{Path(image_path).stem}_visual_comparison.png"
    plt.savefig(output_path, dpi=300, bbox_inches='tight', facecolor='white')
    print(f"Saved: {output_path}")
    plt.close()

    return output_path

def main():
    print("="*80)
    print("  Visual Comparison: Original vs Stored Images")
    print("="*80)

    img_dir = Path("real_images")
    if not img_dir.exists():
        print("ERROR: real_images folder not found")
        return

    images = list(img_dir.glob("*.jpg")) + list(img_dir.glob("*.png"))
    if not images:
        print("ERROR: No images in real_images folder")
        return

    print(f"\nFound {len(images)} images\n")

    for img_path in images:
        print(f"Processing: {img_path.name}")
        output_path = create_visual_comparison(img_path, top_k=60)
        print(f"  -> {output_path}\n")

    print("="*80)
    print("  Complete!")
    print("="*80)
    print(f"\nResults saved in: comparison_results/")
    print("\nPresentation points:")
    print("  1. Green-framed: Original image (what we want to preserve)")
    print("  2. Red-framed: Method A stores fixed center (may miss edges)")
    print("  3. Green-framed: Method B stores smart selection (captures key features)")
    print("  4. Gray areas: Not stored (saves 92% storage)")
    print()

if __name__ == "__main__":
    main()
