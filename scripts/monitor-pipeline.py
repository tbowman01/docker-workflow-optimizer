#!/usr/bin/env python3
"""
Docker Build Pipeline Monitor
Tracks and analyzes build performance metrics
"""

import json
import time
import subprocess
import argparse
from datetime import datetime, timedelta
from typing import Dict, List, Optional
import os
import sys

class PipelineMonitor:
    def __init__(self, registry: str = "ghcr.io", image_name: str = "myapp"):
        self.registry = registry
        self.image_name = image_name
        self.metrics = {
            "builds": [],
            "cache_hits": [],
            "layer_reuse": [],
            "push_times": [],
            "image_sizes": []
        }
    
    def analyze_build_log(self, log_file: str) -> Dict:
        """Analyze Docker build log for metrics"""
        metrics = {
            "timestamp": datetime.now().isoformat(),
            "cache_hits": 0,
            "cache_misses": 0,
            "layers_built": 0,
            "layers_cached": 0,
            "build_time": 0,
            "image_size": 0
        }
        
        if not os.path.exists(log_file):
            return metrics
        
        with open(log_file, 'r') as f:
            lines = f.readlines()
            
        for line in lines:
            if "CACHED" in line:
                metrics["cache_hits"] += 1
                metrics["layers_cached"] += 1
            elif "RUN" in line and "CACHED" not in line:
                metrics["cache_misses"] += 1
                metrics["layers_built"] += 1
            elif "exporting to image" in line:
                # Extract time from build completion
                if "done" in line:
                    parts = line.split()
                    for i, part in enumerate(parts):
                        if part == "done" and i + 1 < len(parts):
                            time_str = parts[i + 1].replace("s", "")
                            try:
                                metrics["build_time"] = float(time_str)
                            except ValueError:
                                pass
        
        # Calculate cache efficiency
        total_layers = metrics["layers_cached"] + metrics["layers_built"]
        if total_layers > 0:
            metrics["cache_efficiency"] = (metrics["layers_cached"] / total_layers) * 100
        else:
            metrics["cache_efficiency"] = 0
        
        return metrics
    
    def get_image_size(self, tag: str = "latest") -> int:
        """Get size of Docker image"""
        try:
            cmd = f"docker images {self.registry}/{self.image_name}:{tag} --format '{{{{.Size}}}}'"
            result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
            if result.returncode == 0:
                size_str = result.stdout.strip()
                # Convert to bytes
                if "GB" in size_str:
                    return int(float(size_str.replace("GB", "")) * 1024 * 1024 * 1024)
                elif "MB" in size_str:
                    return int(float(size_str.replace("MB", "")) * 1024 * 1024)
                elif "KB" in size_str:
                    return int(float(size_str.replace("KB", "")) * 1024)
                else:
                    return int(size_str.replace("B", ""))
        except Exception as e:
            print(f"Error getting image size: {e}")
        return 0
    
    def analyze_registry_performance(self) -> Dict:
        """Analyze registry push/pull performance"""
        metrics = {
            "timestamp": datetime.now().isoformat(),
            "push_time": 0,
            "pull_time": 0,
            "bandwidth_mbps": 0
        }
        
        # Test push performance
        tag = f"test-{int(time.time())}"
        start_time = time.time()
        
        try:
            # Tag image for push test
            subprocess.run(
                f"docker tag {self.registry}/{self.image_name}:latest "
                f"{self.registry}/{self.image_name}:{tag}",
                shell=True, check=True, capture_output=True
            )
            
            # Push to registry
            result = subprocess.run(
                f"docker push {self.registry}/{self.image_name}:{tag}",
                shell=True, capture_output=True, text=True
            )
            
            metrics["push_time"] = time.time() - start_time
            
            # Test pull performance
            subprocess.run(f"docker rmi {self.registry}/{self.image_name}:{tag}", 
                         shell=True, capture_output=True)
            
            start_time = time.time()
            subprocess.run(
                f"docker pull {self.registry}/{self.image_name}:{tag}",
                shell=True, check=True, capture_output=True
            )
            metrics["pull_time"] = time.time() - start_time
            
            # Calculate bandwidth (approximate)
            image_size = self.get_image_size(tag)
            if image_size > 0 and metrics["push_time"] > 0:
                metrics["bandwidth_mbps"] = (image_size / (1024 * 1024)) / metrics["push_time"]
            
            # Cleanup test tag
            subprocess.run(
                f"docker rmi {self.registry}/{self.image_name}:{tag}",
                shell=True, capture_output=True
            )
            
        except subprocess.CalledProcessError as e:
            print(f"Registry performance test failed: {e}")
        
        return metrics
    
    def generate_report(self, output_file: str = "pipeline-metrics.json"):
        """Generate comprehensive metrics report"""
        report = {
            "timestamp": datetime.now().isoformat(),
            "registry": self.registry,
            "image": self.image_name,
            "summary": {
                "total_builds": len(self.metrics["builds"]),
                "average_build_time": 0,
                "average_cache_efficiency": 0,
                "average_image_size": 0,
                "average_push_time": 0
            },
            "detailed_metrics": self.metrics,
            "recommendations": []
        }
        
        # Calculate averages
        if self.metrics["builds"]:
            build_times = [b.get("build_time", 0) for b in self.metrics["builds"]]
            report["summary"]["average_build_time"] = sum(build_times) / len(build_times)
            
            cache_efficiencies = [b.get("cache_efficiency", 0) for b in self.metrics["builds"]]
            report["summary"]["average_cache_efficiency"] = sum(cache_efficiencies) / len(cache_efficiencies)
        
        if self.metrics["image_sizes"]:
            report["summary"]["average_image_size"] = sum(self.metrics["image_sizes"]) / len(self.metrics["image_sizes"])
        
        if self.metrics["push_times"]:
            push_times = [p.get("push_time", 0) for p in self.metrics["push_times"]]
            report["summary"]["average_push_time"] = sum(push_times) / len(push_times)
        
        # Generate recommendations
        if report["summary"]["average_cache_efficiency"] < 70:
            report["recommendations"].append(
                "Cache efficiency is below 70%. Consider optimizing Dockerfile layer ordering."
            )
        
        if report["summary"]["average_build_time"] > 300:
            report["recommendations"].append(
                "Average build time exceeds 5 minutes. Consider using parallel builds or reducing context size."
            )
        
        if report["summary"]["average_image_size"] > 500 * 1024 * 1024:
            report["recommendations"].append(
                "Average image size exceeds 500MB. Consider using multi-stage builds or smaller base images."
            )
        
        # Save report
        with open(output_file, 'w') as f:
            json.dump(report, f, indent=2)
        
        return report
    
    def continuous_monitor(self, interval: int = 60, duration: int = 3600):
        """Continuously monitor pipeline metrics"""
        print(f"Starting continuous monitoring for {duration} seconds...")
        start_time = time.time()
        
        while time.time() - start_time < duration:
            # Collect metrics
            build_metrics = self.analyze_build_log("/tmp/build.log")
            self.metrics["builds"].append(build_metrics)
            
            registry_metrics = self.analyze_registry_performance()
            self.metrics["push_times"].append(registry_metrics)
            
            image_size = self.get_image_size()
            self.metrics["image_sizes"].append(image_size)
            
            # Display current metrics
            print(f"\n[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] Metrics Update:")
            print(f"  Cache Efficiency: {build_metrics.get('cache_efficiency', 0):.1f}%")
            print(f"  Build Time: {build_metrics.get('build_time', 0):.1f}s")
            print(f"  Image Size: {image_size / (1024*1024):.1f}MB")
            print(f"  Push Time: {registry_metrics.get('push_time', 0):.1f}s")
            
            # Generate interim report
            self.generate_report()
            
            # Wait for next interval
            time.sleep(interval)
        
        print("\nMonitoring completed. Generating final report...")
        report = self.generate_report()
        
        print("\n=== Final Report Summary ===")
        print(f"Total Builds: {report['summary']['total_builds']}")
        print(f"Avg Build Time: {report['summary']['average_build_time']:.1f}s")
        print(f"Avg Cache Efficiency: {report['summary']['average_cache_efficiency']:.1f}%")
        print(f"Avg Image Size: {report['summary']['average_image_size'] / (1024*1024):.1f}MB")
        print(f"Avg Push Time: {report['summary']['average_push_time']:.1f}s")
        
        if report['recommendations']:
            print("\n=== Recommendations ===")
            for rec in report['recommendations']:
                print(f"  • {rec}")

def main():
    parser = argparse.ArgumentParser(description="Docker Pipeline Monitor")
    parser.add_argument("--registry", default="ghcr.io", help="Container registry")
    parser.add_argument("--image", default="myapp", help="Image name")
    parser.add_argument("--mode", choices=["analyze", "monitor", "report"], 
                       default="analyze", help="Operation mode")
    parser.add_argument("--duration", type=int, default=3600, 
                       help="Monitoring duration in seconds")
    parser.add_argument("--interval", type=int, default=60, 
                       help="Monitoring interval in seconds")
    parser.add_argument("--log-file", default="/tmp/build.log", 
                       help="Build log file to analyze")
    
    args = parser.parse_args()
    
    monitor = PipelineMonitor(args.registry, args.image)
    
    if args.mode == "analyze":
        metrics = monitor.analyze_build_log(args.log_file)
        print(json.dumps(metrics, indent=2))
    elif args.mode == "monitor":
        monitor.continuous_monitor(args.interval, args.duration)
    elif args.mode == "report":
        report = monitor.generate_report()
        print(json.dumps(report, indent=2))

if __name__ == "__main__":
    main()