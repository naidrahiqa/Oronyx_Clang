#!/usr/bin/env python3
"""Oronyx Clang — Benchmark Chart Generator
Generates multi-panel SVG chart from benchmark results.
Metrics: Compile Time, Binary Size, Peak Memory
Usage: python3 generate-chart.py results.json output.svg
"""
import json
import sys

def fmt_size(b):
    if b >= 1024*1024:
        return f"{b/(1024*1024):.1f}MB"
    elif b >= 1024:
        return f"{b/1024:.1f}KB"
    return f"{b}B"

def fmt_mem(kb):
    if kb >= 1024:
        return f"{kb/1024:.1f}GB"
    return f"{kb}KB"

def generate_svg(results, output_path):
    WIDTH = 900
    PANEL_H = 160
    GAP = 20
    PADDING_TOP = 50
    PADDING_BOT = 40
    PADDING_X = 70
    BAR_W = 60
    BAR_GAP = 30

    COLORS = {
        'no-lto':   '#3b82f6',
        'thin-lto': '#10b981',
        'full-lto': '#f59e0b',
    }

    n = len(results)
    if n == 0:
        return

    panels = [
        ('Compile Time', 'avg_time_ms', 'ms', lambda v: f"{v}ms"),
        ('Binary Size',  'avg_size_bytes', 'bytes', fmt_size),
        ('Peak Memory',  'peak_mem_kb', 'KB', fmt_mem),
    ]

    total_h = PADDING_TOP + len(panels) * PANEL_H + (len(panels) - 1) * GAP + PADDING_BOT

    svg_parts = [f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {WIDTH} {total_h}">
<defs>
  <linearGradient id="bg" x1="0%" y1="0%" x2="0%" y2="100%">
    <stop offset="0%" style="stop-color:#1e293b"/>
    <stop offset="100%" style="stop-color:#0f172a"/>
  </linearGradient>
  <filter id="shadow" x="-20%" y="-20%" width="140%" height="140%">
    <feDropShadow dx="1" dy="1" stdDeviation="2" flood-opacity="0.3"/>
  </filter>
</defs>
<rect width="{WIDTH}" height="{total_h}" fill="url(#bg)" rx="12"/>
<text x="{WIDTH//2}" y="30" text-anchor="middle" fill="#e2e8f0" font-family="system-ui, sans-serif" font-size="16" font-weight="bold">
  Oronyx Clang {results[0].get('version','')} Benchmark
</text>
''']

    for pi, (title, key, unit, fmt_fn) in enumerate(panels):
        y_off = PADDING_TOP + pi * (PANEL_H + GAP)
        chart_h = PANEL_H - 30
        chart_w = WIDTH - 2 * PADDING_X

        max_val = max(r[key] for r in results) * 1.15 if results else 1
        scale = chart_h / max_val if max_val > 0 else 1

        svg_parts.append(f'<text x="14" y="{y_off + PANEL_H//2}" text-anchor="middle" fill="#94a3b8" font-family="system-ui, sans-serif" font-size="11" transform="rotate(-90,14,{y_off + PANEL_H//2})">{title}</text>')

        for i in range(4):
            gy = y_off + 10 + chart_h - (chart_h * i / 3)
            svg_parts.append(f'<line x1="{PADDING_X}" y1="{gy}" x2="{WIDTH-PADDING_X}" y2="{gy}" stroke="#334155" stroke-width="0.5"/>')
            val = max_val * i / 3
            svg_parts.append(f'<text x="{PADDING_X-5}" y="{gy+4}" text-anchor="end" fill="#64748b" font-family="system-ui, sans-serif" font-size="9">{fmt_fn(val)}</text>')

        bar_total = BAR_W * n + BAR_GAP * (n - 1)
        start_x = PADDING_X + (chart_w - bar_total) / 2

        for i, r in enumerate(results):
            bx = start_x + i * (BAR_W + BAR_GAP)
            val = r[key]
            bh = val * scale
            by = y_off + 10 + chart_h - bh
            color = COLORS.get(r.get('lto', 'off'), '#64748b')

            svg_parts.append(f'''<g filter="url(#shadow)">
  <rect x="{bx}" y="{by}" width="{BAR_W}" height="{bh}" fill="{color}" rx="4"/>
  <text x="{bx+BAR_W//2}" y="{by-4}" text-anchor="middle" fill="#e2e8f0" font-family="system-ui, sans-serif" font-size="10" font-weight="bold">{fmt_fn(val)}</text>
</g>''')

            if pi == len(panels) - 1:
                svg_parts.append(f'<text x="{bx+BAR_W//2}" y="{y_off+chart_h+18}" text-anchor="middle" fill="#cbd5e1" font-family="system-ui, sans-serif" font-size="10">{r["name"]}</text>')

        svg_parts.append(f'<rect x="{PADDING_X}" y="{y_off+10}" width="{chart_w}" height="{chart_h}" fill="none" stroke="#334155" stroke-width="1" rx="4"/>')

    legend_y = total_h - 14
    legend_x = PADDING_X
    for lto, color in COLORS.items():
        if any(r.get('lto') == lto for r in results):
            svg_parts.append(f'<rect x="{legend_x}" y="{legend_y-8}" width="10" height="10" fill="{color}" rx="2"/>')
            svg_parts.append(f'<text x="{legend_x+14}" y="{legend_y}" fill="#94a3b8" font-family="system-ui, sans-serif" font-size="9">{lto}</text>')
            legend_x += 80

    svg_parts.append('</svg>')

    with open(output_path, 'w') as f:
        f.write('\n'.join(svg_parts))

    print(f"Chart generated: {output_path}")

def main():
    if len(sys.argv) < 3:
        print("Usage: python3 generate-chart.py <results.json> <output.svg>")
        sys.exit(1)

    with open(sys.argv[1]) as f:
        results = json.load(f)

    generate_svg(results, sys.argv[2])

if __name__ == '__main__':
    main()
