"""
Visual Comparison with Bounding Boxes
Show which regions are selected (highlighted on original image)
"""

import matplotlib
matplotlib.use('Agg')

import numpy as np
from PIL import Image
import matplotlib.pyplot as plt
import matplotlib.patches as patches
from pathlib import Path

class PyramidProcessor:
    def __init__(self):
        self.patch_size = 14
        self.image_size = 224

    def extract_patches(self, image):
        patches_list = []
        positions = []
        h, w = image.shape[0], image.shape[1]
        for i in range(0, h, self.patch_size):
            for j in range(0, w, self.patch_size):
                patch = image[i:i+self.patch_size, j:j+self.patch_size, :]
                if patch.shape[0] == self.patch_size and patch.shape[1] == self.patch_size:
                    patches_list.append(patch)
                    positions.append((i, j))
        return np.array(patches_list), positions

    def compute_complexity(self, patch):
        gray = 0.299 * patch[:,:,0] + 0.587 * patch[:,:,1] + 0.114 * patch[:,:,2]
        grad_x = np.abs(np.diff(gray, axis=1))
        grad_y = np.abs(np.diff(gray, axis=0))
        return np.mean(grad_x) + np.mean(grad_y)

    def compute_interest_map(self, image):
        patches_list, positions = self.extract_patches(image)
        grid_size = self.image_size // self.patch_size
        interest_map = np.zeros((grid_size, grid_size))
        for idx, patch in enumerate(patches_list):
            i = idx // grid_size
            j = idx % grid_size
            interest_map[i, j] = self.compute_complexity(patch)
        return interest_map, patches_list, positions

    def get_selected_boxes(self, image, top_k=60):
        """获取智能选择的区域"""
        interest_map, _, positions = self.compute_interest_map(image)
        flat_interest = interest_map.flatten()
        top_indices = np.argsort(flat_interest)[-top_k:][::-1]

        selected_boxes = [positions[idx] for idx in top_indices if idx < len(positions)]

        grid_size = self.image_size // self.patch_size
        mask = np.zeros((grid_size, grid_size))
        for idx in top_indices:
            if idx < len(positions):
                grid_i = idx // grid_size
                grid_j = idx % grid_size
                mask[grid_i, grid_j] = 1

        return selected_boxes, mask, interest_map

    def get_center_boxes(self, top_k=60):
        """获取中心区域"""
        grid_size = self.image_size // self.patch_size
        center_size = int(np.sqrt(top_k))
        start = (grid_size - center_size) // 2

        boxes = []
        for i in range(start, start+center_size):
            for j in range(start, start+center_size):
                if i < grid_size and j < grid_size:
                    y = i * self.patch_size
                    x = j * self.patch_size
                    boxes.append((y, x))

        mask = np.zeros((grid_size, grid_size))
        mask[start:start+center_size, start:start+center_size] = 1

        return boxes[:top_k], mask

def create_highlight_comparison(image_path, top_k=60):
    processor = PyramidProcessor()
    img = Image.open(image_path).convert('RGB')
    img = img.resize((224, 224))
    img_array = np.array(img)

    # 获取选择的区域
    smart_boxes, mask_smart, interest_map = processor.get_selected_boxes(img_array, top_k)
    center_boxes, mask_center = processor.get_center_boxes(top_k)

    total_patches = 16 * 16
    saved = (1 - top_k / total_patches) * 100

    # 创建可视化
    fig = plt.figure(figsize=(24, 8))

    # === Row 1: Method A (Fixed Center) ===

    # Original
    ax1 = plt.subplot(2, 4, 1)
    ax1.imshow(img)
    ax1.set_title("Original Image\n(Baseline: 256 patches)", fontsize=13, fontweight='bold', pad=10)
    ax1.axis('off')

    # Interest Map
    ax2 = plt.subplot(2, 4, 2)
    im1 = ax2.imshow(interest_map, cmap='hot', interpolation='bilinear')
    ax2.set_title("Interest Map\n(Complexity Analysis)", fontsize=13, fontweight='bold', pad=10)
    ax2.axis('off')
    plt.colorbar(im1, ax=ax2, fraction=0.046)

    # Method A: Highlighted
    ax3 = plt.subplot(2, 4, 3)
    ax3.imshow(img)
    # Draw red boxes
    for (y, x) in center_boxes:
        rect = patches.Rectangle((x, y), processor.patch_size, processor.patch_size,
                                 linewidth=1, edgecolor='red', facecolor='none', alpha=0.6)
        ax3.add_patch(rect)
    ax3.set_title(f"Method A: Fixed Center\n(Red = Selected {top_k} patches)",
                  fontsize=13, fontweight='bold', pad=10, color='red')
    ax3.axis('off')

    # Stats A
    ax4 = plt.subplot(2, 4, 4)
    ax4.axis('off')
    stats_a = f"""
Method A: Fixed Center

Strategy:
  Always select center
  regardless of content

Storage:
  {top_k}/256 patches
  Saved: {saved:.1f}%

Issue:
  • Fixed strategy
  • May miss edges
  • Not adaptive

Visual:
  Red boxes show
  what gets stored
    """
    ax4.text(0.1, 0.5, stats_a, fontsize=11, family='monospace', va='center',
             bbox=dict(boxstyle='round,pad=1', fc='#ffcccc', ec='red', lw=2, alpha=0.8))

    # === Row 2: Method B (Smart Selection) ===

    # Original
    ax5 = plt.subplot(2, 4, 5)
    ax5.imshow(img)
    ax5.set_title("Original Image\n(Baseline: 256 patches)", fontsize=13, fontweight='bold', pad=10)
    ax5.axis('off')

    # Interest Map (repeat)
    ax6 = plt.subplot(2, 4, 6)
    im2 = ax6.imshow(interest_map, cmap='hot', interpolation='bilinear')
    ax6.set_title("Interest Map\n(Complexity Analysis)", fontsize=13, fontweight='bold', pad=10)
    ax6.axis('off')
    plt.colorbar(im2, ax=ax6, fraction=0.046)

    # Method B: Highlighted
    ax7 = plt.subplot(2, 4, 7)
    ax7.imshow(img)
    # Draw green boxes
    for (y, x) in smart_boxes:
        rect = patches.Rectangle((x, y), processor.patch_size, processor.patch_size,
                                 linewidth=1, edgecolor='lime', facecolor='none', alpha=0.7)
        ax7.add_patch(rect)
    ax7.set_title(f"Method B: Smart Selection\n(Green = Selected {top_k} patches)",
                  fontsize=13, fontweight='bold', pad=10, color='green')
    ax7.axis('off')

    # Stats B
    ax8 = plt.subplot(2, 4, 8)
    ax8.axis('off')
    stats_b = f"""
Method B: Smart Selection
(My Design)

Strategy:
  Auto-detect important
  regions adaptively

Storage:
  {top_k}/256 patches
  Saved: {saved:.1f}%

Advantage:
  • Content-aware
  • Captures key features
  • Adaptive strategy

Visual:
  Green boxes follow
  image complexity
    """
    ax8.text(0.1, 0.5, stats_b, fontsize=11, family='monospace', va='center',
             bbox=dict(boxstyle='round,pad=1', fc='#ccffcc', ec='green', lw=2, alpha=0.8))

    # Title
    fig.suptitle(f'Region Selection Comparison: Fixed Center vs Smart Selection\n'
                 f'Both save {saved:.0f}% storage, but smart selection adapts to image content',
                 fontsize=17, fontweight='bold', y=0.98)

    plt.tight_layout(rect=[0, 0, 1, 0.96])

    # Save
    output_dir = Path("comparison_results")
    output_dir.mkdir(exist_ok=True)
    output_path = output_dir / f"{Path(image_path).stem}_highlight_k{top_k}.png"
    plt.savefig(output_path, dpi=300, bbox_inches='tight', facecolor='white')
    print(f"Saved: {output_path}")
    plt.close()

    return output_path

def main():
    print("="*80)
    print("  Highlight Comparison: Which Regions Get Selected?")
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

    # Generate with Top-60
    for img_path in images:
        print(f"Processing: {img_path.name}")
        output_path = create_highlight_comparison(img_path, top_k=60)
        print(f"  -> {output_path}\n")

    print("="*80)
    print("  Complete!")
    print("="*80)
    print(f"\nResults saved in: comparison_results/")
    print("\nPresentation points:")
    print("  1. Red boxes (Method A): Fixed center selection")
    print("  2. Green boxes (Method B): Smart adaptive selection")
    print("  3. Notice: Green boxes follow the hot regions in interest map")
    print("  4. Both save 77% storage, but green captures key features better")
    print()

if __name__ == "__main__":
    main()
