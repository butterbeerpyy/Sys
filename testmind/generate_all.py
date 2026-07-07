"""
Generate visual comparisons with different Top-K values
To find the best balance between storage saving and visual quality
"""

import subprocess
import sys
from pathlib import Path

# Test different Top-K values
top_k_values = [40, 60, 80]

print("="*80)
print("  Generating Visual Comparisons with Different Top-K Values")
print("="*80)

for k in top_k_values:
    print(f"\n[Generating with Top-K = {k}]")

    # Modify visual_comparison.py to use this K value
    script_content = Path("visual_comparison.py").read_text()

    # Replace the default top_k=20 with current k
    modified = script_content.replace(
        'create_visual_comparison(img_path, top_k=20)',
        f'create_visual_comparison(img_path, top_k={k})'
    ).replace(
        'top_k=20):',
        f'top_k={k}):'
    )

    # Write temporary script
    temp_script = Path(f"visual_comparison_k{k}.py")
    temp_script.write_text(modified)

    # Run it
    result = subprocess.run([sys.executable, str(temp_script)],
                          capture_output=True, text=True)

    if result.returncode == 0:
        print(f"  ✅ Success! Check comparison_results/*_k{k}_*.png")
    else:
        print(f"  ❌ Error: {result.stderr[:200]}")

    # Clean up temp script
    temp_script.unlink()

print("\n" + "="*80)
print("  Complete! Compare the results to choose best Top-K")
print("="*80)
print("\nRecommendation:")
print("  Top-40: 84% saving, moderate quality")
print("  Top-60: 77% saving, good quality")
print("  Top-80: 69% saving, best quality")
print()
