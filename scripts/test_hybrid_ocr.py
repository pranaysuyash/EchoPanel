#!/usr/bin/env python3
"""
Hybrid OCR Test Script

Tests the hybrid OCR pipeline with various slide types:
- Text slides
- Charts (bar, line, pie)
- Tables
- Mixed content

Usage:
    python scripts/test_hybrid_ocr.py
    python scripts/test_hybrid_ocr.py --mode paddle_only
    python scripts/test_hybrid_ocr.py --save-results ./results.json
"""

import argparse
import asyncio
import io
import json
import os
import sys
import time
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import List, Optional

import numpy as np
from PIL import Image, ImageDraw, ImageFont

# Add server to path
sys.path.insert(0, str(Path(__file__).parent.parent / "server"))

from services.ocr_hybrid import HybridOCRPipeline, OCRMode, VLMTriggerMode


@dataclass
class TestResult:
    """Result from a single test."""
    test_name: str
    slide_type: str
    primary_text: str
    semantic_summary: str
    key_insights: List[str]
    entities: List[dict]
    confidence: float
    source: str
    engines_used: List[str]
    processing_time_ms: float
    is_enriched: bool
    layout_type: str


class SlideGenerator:
    """Generate test slides of various types."""
    
    def __init__(self, width: int = 1280, height: int = 720):
        self.width = width
        self.height = height
        self.font_large = None
        self.font_medium = None
        self.font_small = None
        self._load_fonts()
    
    def _load_fonts(self):
        """Load fonts (fallback to default if not available)."""
        try:
            self.font_large = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 48)
            self.font_medium = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 32)
            self.font_small = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 20)
        except:
            self.font_large = ImageFont.load_default()
            self.font_medium = ImageFont.load_default()
            self.font_small = ImageFont.load_default()
    
    def text_slide(self, title: str = "Q3 2024 Financial Results") -> Image.Image:
        """Generate a text-heavy slide."""
        img = Image.new('RGB', (self.width, self.height), color='white')
        draw = ImageDraw.Draw(img)
        
        # Title
        draw.text((60, 50), title, fill='black', font=self.font_large)
        
        # Bullet points
        bullets = [
            "• Revenue: $5.2M (+15% YoY)",
            "• Net Income: $1.3M (+22% YoY)",
            "• User Growth: +8,500 new users",
            "• Churn Rate: 2.1% (down from 2.8%)",
            "• ARR: $20.8M (annual recurring revenue)"
        ]
        y = 150
        for bullet in bullets:
            draw.text((60, y), bullet, fill='black', font=self.font_medium)
            y += 60
        
        # Footer
        draw.text((60, self.height - 60), "Confidential - Internal Use Only", 
                 fill='gray', font=self.font_small)
        
        return img
    
    def chart_slide(self) -> Image.Image:
        """Generate a bar chart slide."""
        img = Image.new('RGB', (self.width, self.height), color='white')
        draw = ImageDraw.Draw(img)
        
        # Title
        draw.text((60, 30), "Monthly Revenue Growth", fill='black', font=self.font_large)
        
        # Chart data
        months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun"]
        values = [3.2, 3.5, 3.8, 4.2, 4.8, 5.2]  # in millions
        max_val = 6.0
        
        # Chart area
        chart_top = 150
        chart_bottom = 550
        chart_left = 150
        chart_right = 1100
        
        # Draw axes
        draw.line([(chart_left, chart_bottom), (chart_right, chart_bottom)], 
                 fill='black', width=2)
        draw.line([(chart_left, chart_top), (chart_left, chart_bottom)], 
                 fill='black', width=2)
        
        # Draw bars
        bar_width = (chart_right - chart_left - 100) // len(months)
        colors = ['#FF6B6B', '#4ECDC4', '#45B7D1', '#FFA07A', '#98D8C8', '#F7DC6F']
        
        for i, (month, val) in enumerate(zip(months, values)):
            bar_height = (val / max_val) * (chart_bottom - chart_top - 50)
            x = chart_left + 50 + i * (bar_width + 20)
            y = chart_bottom - bar_height
            
            # Bar
            draw.rectangle([(x, y), (x + bar_width, chart_bottom)], 
                          fill=colors[i], outline='black', width=2)
            
            # Value label
            draw.text((x + bar_width//2 - 30, y - 30), f"${val}M", 
                     fill='black', font=self.font_small)
            
            # Month label
            draw.text((x + 10, chart_bottom + 10), month, 
                     fill='black', font=self.font_small)
        
        return img
    
    def table_slide(self) -> Image.Image:
        """Generate a table slide."""
        img = Image.new('RGB', (self.width, self.height), color='white')
        draw = ImageDraw.Draw(img)
        
        # Title
        draw.text((60, 30), "Product Performance Matrix", fill='black', font=self.font_large)
        
        # Table data
        headers = ["Product", "Revenue", "Growth", "Users", "Satisfaction"]
        rows = [
            ["Product A", "$2.1M", "+25%", "12,450", "4.8/5"],
            ["Product B", "$1.8M", "+18%", "9,200", "4.6/5"],
            ["Product C", "$0.9M", "+45%", "5,100", "4.9/5"],
            ["Product D", "$0.4M", "-5%", "2,800", "3.9/5"],
        ]
        
        # Draw table
        cell_height = 60
        col_widths = [200, 150, 150, 150, 150]
        start_x = 100
        start_y = 120
        
        # Header row
        x = start_x
        for i, header in enumerate(headers):
            draw.rectangle([(x, start_y), (x + col_widths[i], start_y + cell_height)],
                          fill='#333333', outline='black')
            draw.text((x + 10, start_y + 15), header, fill='white', font=self.font_medium)
            x += col_widths[i]
        
        # Data rows
        for row_idx, row in enumerate(rows):
            y = start_y + (row_idx + 1) * cell_height
            x = start_x
            bg_color = '#F0F0F0' if row_idx % 2 == 0 else 'white'
            
            for col_idx, cell in enumerate(row):
                draw.rectangle([(x, y), (x + col_widths[col_idx], y + cell_height)],
                              fill=bg_color, outline='black')
                draw.text((x + 10, y + 15), cell, fill='black', font=self.font_small)
                x += col_widths[col_idx]
        
        return img
    
    def diagram_slide(self) -> Image.Image:
        """Generate a flowchart/diagram slide."""
        img = Image.new('RGB', (self.width, self.height), color='white')
        draw = ImageDraw.Draw(img)
        
        # Title
        draw.text((60, 30), "Customer Journey Flow", fill='black', font=self.font_large)
        
        # Draw boxes
        boxes = [
            (100, 150, "Awareness\n(Ads, Content)", '#FF6B6B'),
            (400, 150, "Consideration\n(Demo, Trial)", '#4ECDC4'),
            (700, 150, "Purchase\n(Onboarding)", '#45B7D1'),
            (1000, 150, "Retention\n(Support, Updates)", '#98D8C8'),
        ]
        
        for x, y, text, color in boxes:
            # Box
            draw.rounded_rectangle([(x, y), (x + 250, y + 120)], 
                                  radius=10, fill=color, outline='black', width=2)
            # Text
            lines = text.split('\n')
            line_y = y + 30
            for line in lines:
                draw.text((x + 20, line_y), line, fill='black', font=self.font_small)
                line_y += 25
            
            # Arrow to next
            if x < 900:
                draw.polygon([(x + 260, y + 50), (x + 290, y + 60), (x + 260, y + 70)],
                           fill='black')
        
        # Metrics below
        metrics = [
            "Conversion Rate: 12% → 35%",
            "Avg. Time to Purchase: 14 days",
            "Customer LTV: $2,400"
        ]
        y = 350
        for metric in metrics:
            draw.text((100, y), f"• {metric}", fill='black', font=self.font_medium)
            y += 50
        
        return img


class HybridOCRTester:
    """Test the hybrid OCR pipeline."""
    
    def __init__(self, mode: OCRMode = OCRMode.HYBRID, 
                 vlm_trigger: VLMTriggerMode = VLMTriggerMode.ADAPTIVE):
        self.pipeline = HybridOCRPipeline(mode=mode, vlm_trigger=vlm_trigger)
        self.generator = SlideGenerator()
        self.results: List[TestResult] = []
    
    async def run_tests(self, verbose: bool = True) -> List[TestResult]:
        """Run all test cases."""
        if not self.pipeline.is_available():
            print("❌ OCR pipeline not available!")
            return []
        
        test_cases = [
            ("text_financial", "Text: Financial", self.generator.text_slide),
            ("chart_bar", "Chart: Bar", self.generator.chart_slide),
            ("table_performance", "Table: Performance", self.generator.table_slide),
            ("diagram_flow", "Diagram: Flow", self.generator.diagram_slide),
        ]
        
        print(f"\n🧪 Running {len(test_cases)} test cases...")
        print(f"   Mode: {self.pipeline.mode.value}")
        print(f"   VLM Trigger: {self.pipeline.vlm_trigger.value}")
        print()
        
        for test_id, test_name, gen_func in test_cases:
            if verbose:
                print(f"Testing: {test_name}...")
            
            # Generate slide
            img = gen_func()
            
            # Convert to bytes
            buffer = io.BytesIO()
            img.save(buffer, format='PNG')
            image_bytes = buffer.getvalue()
            
            # Process
            start = time.time()
            result = await self.pipeline.process_frame(image_bytes, skip_duplicates=False)
            elapsed = (time.time() - start) * 1000
            
            # Record result
            test_result = TestResult(
                test_name=test_id,
                slide_type=test_name,
                primary_text=result.primary_text[:500],
                semantic_summary=result.semantic_summary or "",
                key_insights=result.key_insights,
                entities=[{"text": e.text, "type": e.type} for e in result.entities],
                confidence=result.confidence,
                source=result.source,
                engines_used=result.engines_used,
                processing_time_ms=result.processing_time_ms,
                is_enriched=result.is_enriched,
                layout_type=result.layout_type.value
            )
            self.results.append(test_result)
            
            if verbose:
                print(f"   ✓ Source: {result.source}")
                print(f"   ✓ Confidence: {result.confidence:.1f}%")
                print(f"   ✓ Time: {result.processing_time_ms:.0f}ms")
                print(f"   ✓ Layout: {result.layout_type.value}")
                print(f"   ✓ Enriched: {result.is_enriched}")
                if result.semantic_summary:
                    print(f"   ✓ Summary: {result.semantic_summary[:80]}...")
                print()
        
        return self.results
    
    def print_summary(self):
        """Print test summary."""
        print("\n" + "="*60)
        print("📊 TEST SUMMARY")
        print("="*60)
        
        total_time = sum(r.processing_time_ms for r in self.results)
        avg_time = total_time / len(self.results) if self.results else 0
        enriched_count = sum(1 for r in self.results if r.is_enriched)
        
        print(f"\nTotal tests: {len(self.results)}")
        print(f"Average time: {avg_time:.0f}ms")
        print(f"Enriched results: {enriched_count}/{len(self.results)}")
        
        # Engine usage
        sources = {}
        for r in self.results:
            sources[r.source] = sources.get(r.source, 0) + 1
        print(f"\nEngine usage:")
        for source, count in sources.items():
            print(f"  • {source}: {count}")
        
        # Layout detection
        layouts = {}
        for r in self.results:
            layouts[r.layout_type] = layouts.get(r.layout_type, 0) + 1
        print(f"\nLayout detection:")
        for layout, count in layouts.items():
            print(f"  • {layout}: {count}")
        
        print()
    
    def save_results(self, filepath: str):
        """Save results to JSON."""
        data = {
            "pipeline_config": {
                "mode": self.pipeline.mode.value,
                "vlm_trigger": self.pipeline.vlm_trigger.value,
                "confidence_threshold": self.pipeline.confidence_threshold,
            },
            "results": [asdict(r) for r in self.results],
            "summary": {
                "total_tests": len(self.results),
                "avg_time_ms": sum(r.processing_time_ms for r in self.results) / len(self.results) if self.results else 0,
                "enriched_count": sum(1 for r in self.results if r.is_enriched),
            }
        }
        
        with open(filepath, 'w') as f:
            json.dump(data, f, indent=2)
        
        print(f"✅ Results saved to: {filepath}")


async def main():
    parser = argparse.ArgumentParser(description="Test Hybrid OCR Pipeline")
    parser.add_argument("--mode", choices=["hybrid", "paddle_only", "vlm_only"], 
                       default="hybrid", help="OCR mode")
    parser.add_argument("--vlm-trigger", choices=["adaptive", "always", "never"],
                       default="adaptive", help="VLM trigger mode")
    parser.add_argument("--save-results", type=str, help="Save results to JSON file")
    parser.add_argument("--quiet", action="store_true", help="Minimal output")
    
    args = parser.parse_args()
    
    mode = OCRMode(args.mode)
    trigger = VLMTriggerMode(args.vlm_trigger)
    
    tester = HybridOCRTester(mode=mode, vlm_trigger=trigger)
    await tester.run_tests(verbose=not args.quiet)
    
    if not args.quiet:
        tester.print_summary()
    
    if args.save_results:
        tester.save_results(args.save_results)
    
    # Print pipeline stats
    stats = tester.pipeline.get_status()["pipeline_stats"]
    if not args.quiet:
        print("Pipeline Statistics:")
        print(f"  Frames processed: {stats.get('frames_processed', 0)}")
        print(f"  VLM usage rate: {stats.get('vlm_usage_rate', 0)*100:.1f}%")
        print(f"  Estimated avg latency: {stats.get('estimated_avg_latency_ms', 0):.0f}ms")


if __name__ == "__main__":
    asyncio.run(main())
