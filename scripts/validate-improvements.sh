#!/bin/bash
# Docker Workflow Performance Validation Script
# Compares before/after metrics to validate improvements

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
REGISTRY="${REGISTRY:-ghcr.io}"
IMAGE_NAME="${IMAGE_NAME:-myapp}"
TEST_ITERATIONS="${TEST_ITERATIONS:-3}"

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Function to measure build time
measure_build_time() {
    local dockerfile="$1"
    local use_cache="$2"
    local iterations="$3"
    
    local total_time=0
    local successful_builds=0
    
    for i in $(seq 1 $iterations); do
        log_info "Build iteration $i/$iterations with dockerfile: $dockerfile, cache: $use_cache"
        
        # Clear cache if requested
        if [ "$use_cache" = "false" ]; then
            docker builder prune -f > /dev/null 2>&1
        fi
        
        local start_time=$(date +%s.%N)
        
        if docker buildx build \
            --platform "linux/amd64" \
            --file "$dockerfile" \
            --tag "${IMAGE_NAME}:test-${i}" \
            $([ "$use_cache" = "false" ] && echo "--no-cache") \
            . > /tmp/build-${dockerfile##*/}-${use_cache}-${i}.log 2>&1; then
            
            local end_time=$(date +%s.%N)
            local build_time=$(echo "$end_time - $start_time" | bc -l)
            total_time=$(echo "$total_time + $build_time" | bc -l)
            successful_builds=$((successful_builds + 1))
            
            log_info "Build $i completed in ${build_time}s"
        else
            log_error "Build $i failed"
        fi
        
        # Cleanup test image
        docker rmi "${IMAGE_NAME}:test-${i}" > /dev/null 2>&1 || true
    done
    
    if [ $successful_builds -gt 0 ]; then
        local average_time=$(echo "scale=2; $total_time / $successful_builds" | bc -l)
        echo "$average_time"
    else
        echo "0"
    fi
}

# Function to measure image size
measure_image_size() {
    local dockerfile="$1"
    local tag="${2:-test-size}"
    
    if docker buildx build \
        --platform "linux/amd64" \
        --file "$dockerfile" \
        --tag "${IMAGE_NAME}:${tag}" \
        . > /tmp/size-build.log 2>&1; then
        
        local size_bytes=$(docker images "${IMAGE_NAME}:${tag}" --format "{{.Size}}" | head -1)
        
        # Convert to bytes
        local size_in_bytes=0
        if [[ $size_bytes =~ ([0-9.]+)([A-Z]+) ]]; then
            local number=${BASH_REMATCH[1]}
            local unit=${BASH_REMATCH[2]}
            
            case $unit in
                "GB") size_in_bytes=$(echo "$number * 1024 * 1024 * 1024" | bc -l) ;;
                "MB") size_in_bytes=$(echo "$number * 1024 * 1024" | bc -l) ;;
                "KB") size_in_bytes=$(echo "$number * 1024" | bc -l) ;;
                "B") size_in_bytes=$number ;;
            esac
        fi
        
        docker rmi "${IMAGE_NAME}:${tag}" > /dev/null 2>&1 || true
        echo "${size_in_bytes%.*}"  # Remove decimal part
    else
        echo "0"
    fi
}

# Function to analyze build log for cache efficiency
analyze_cache_efficiency() {
    local log_file="$1"
    
    if [ ! -f "$log_file" ]; then
        echo "0"
        return
    fi
    
    local cached_layers=$(grep -c "CACHED" "$log_file" || echo "0")
    local total_layers=$(grep -c "Step [0-9]" "$log_file" || echo "1")
    
    if [ "$total_layers" -gt 0 ]; then
        local efficiency=$(echo "scale=2; ($cached_layers / $total_layers) * 100" | bc -l)
        echo "$efficiency"
    else
        echo "0"
    fi
}

# Function to run comprehensive validation
run_validation() {
    log_info "Starting Docker workflow performance validation..."
    
    # Check for required files
    local original_dockerfile="Dockerfile"
    local optimized_dockerfile="src/Dockerfile.optimized"
    
    # Create a basic Dockerfile if original doesn't exist
    if [ ! -f "$original_dockerfile" ]; then
        log_warning "Original Dockerfile not found, creating a basic one for comparison"
        cat > "$original_dockerfile" <<EOF
FROM node:20
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
RUN npm run build
EXPOSE 3000
CMD ["npm", "start"]
EOF
    fi
    
    if [ ! -f "$optimized_dockerfile" ]; then
        log_error "Optimized Dockerfile not found at $optimized_dockerfile"
        exit 1
    fi
    
    # Create package.json if it doesn't exist
    if [ ! -f "package.json" ]; then
        cat > "package.json" <<EOF
{
  "name": "test-app",
  "version": "1.0.0",
  "scripts": {
    "build": "echo 'Building...'",
    "start": "echo 'Starting...'"
  },
  "dependencies": {
    "express": "^4.18.0"
  }
}
EOF
    fi
    
    log_info "Measuring baseline performance (original Dockerfile)..."
    local baseline_build_time_no_cache=$(measure_build_time "$original_dockerfile" "false" $TEST_ITERATIONS)
    local baseline_build_time_cache=$(measure_build_time "$original_dockerfile" "true" $TEST_ITERATIONS)
    local baseline_image_size=$(measure_image_size "$original_dockerfile" "baseline")
    local baseline_cache_efficiency=$(analyze_cache_efficiency "/tmp/build-${original_dockerfile##*/}-true-1.log")
    
    log_info "Measuring optimized performance..."
    local optimized_build_time_no_cache=$(measure_build_time "$optimized_dockerfile" "false" $TEST_ITERATIONS)
    local optimized_build_time_cache=$(measure_build_time "$optimized_dockerfile" "true" $TEST_ITERATIONS)
    local optimized_image_size=$(measure_image_size "$optimized_dockerfile" "optimized")
    local optimized_cache_efficiency=$(analyze_cache_efficiency "/tmp/build-${optimized_dockerfile##*/}-true-1.log")
    
    # Calculate improvements
    local build_improvement_no_cache=0
    local build_improvement_cache=0
    local size_improvement=0
    local cache_improvement=0
    
    if [ "$(echo "$baseline_build_time_no_cache > 0" | bc -l)" -eq 1 ]; then
        build_improvement_no_cache=$(echo "scale=1; (($baseline_build_time_no_cache - $optimized_build_time_no_cache) / $baseline_build_time_no_cache) * 100" | bc -l)
    fi
    
    if [ "$(echo "$baseline_build_time_cache > 0" | bc -l)" -eq 1 ]; then
        build_improvement_cache=$(echo "scale=1; (($baseline_build_time_cache - $optimized_build_time_cache) / $baseline_build_time_cache) * 100" | bc -l)
    fi
    
    if [ "$baseline_image_size" -gt 0 ]; then
        size_improvement=$(echo "scale=1; (($baseline_image_size - $optimized_image_size) / $baseline_image_size) * 100" | bc -l)
    fi
    
    if [ "$(echo "$baseline_cache_efficiency > 0" | bc -l)" -eq 1 ]; then
        cache_improvement=$(echo "scale=1; $optimized_cache_efficiency - $baseline_cache_efficiency" | bc -l)
    fi
    
    # Generate report
    log_success "Validation completed! Generating report..."
    
    cat > validation-report.json <<EOF
{
    "timestamp": "$(date -Iseconds)",
    "test_iterations": $TEST_ITERATIONS,
    "baseline": {
        "build_time_no_cache": $baseline_build_time_no_cache,
        "build_time_with_cache": $baseline_build_time_cache,
        "image_size_bytes": $baseline_image_size,
        "cache_efficiency_percent": $baseline_cache_efficiency
    },
    "optimized": {
        "build_time_no_cache": $optimized_build_time_no_cache,
        "build_time_with_cache": $optimized_build_time_cache,
        "image_size_bytes": $optimized_image_size,
        "cache_efficiency_percent": $optimized_cache_efficiency
    },
    "improvements": {
        "build_time_no_cache_percent": $build_improvement_no_cache,
        "build_time_with_cache_percent": $build_improvement_cache,
        "image_size_reduction_percent": $size_improvement,
        "cache_efficiency_improvement": $cache_improvement
    }
}
EOF
    
    # Display results
    echo
    echo "================================"
    echo "     VALIDATION RESULTS"
    echo "================================"
    echo
    printf "%-35s %-15s %-15s %-15s\n" "Metric" "Baseline" "Optimized" "Improvement"
    echo "--------------------------------------------------------------------------------"
    printf "%-35s %-15.2f %-15.2f %-15s\n" "Build Time (no cache, seconds)" "$baseline_build_time_no_cache" "$optimized_build_time_no_cache" "${build_improvement_no_cache}%"
    printf "%-35s %-15.2f %-15.2f %-15s\n" "Build Time (cached, seconds)" "$baseline_build_time_cache" "$optimized_build_time_cache" "${build_improvement_cache}%"
    printf "%-35s %-15.1f %-15.1f %-15s\n" "Image Size (MB)" "$(echo "scale=1; $baseline_image_size / 1024 / 1024" | bc -l)" "$(echo "scale=1; $optimized_image_size / 1024 / 1024" | bc -l)" "${size_improvement}%"
    printf "%-35s %-15s %-15s %-15s\n" "Cache Efficiency (%)" "${baseline_cache_efficiency}" "${optimized_cache_efficiency}" "+${cache_improvement}%"
    echo
    
    # Success criteria
    local success=true
    
    if [ "$(echo "$build_improvement_no_cache < 30" | bc -l)" -eq 1 ]; then
        log_warning "Build time improvement (${build_improvement_no_cache}%) is below target (30%)"
        success=false
    fi
    
    if [ "$(echo "$size_improvement < 40" | bc -l)" -eq 1 ]; then
        log_warning "Image size reduction (${size_improvement}%) is below target (40%)"
        success=false
    fi
    
    if [ "$(echo "$optimized_cache_efficiency < 70" | bc -l)" -eq 1 ]; then
        log_warning "Cache efficiency (${optimized_cache_efficiency}%) is below target (70%)"
        success=false
    fi
    
    if [ "$success" = true ]; then
        log_success "All performance targets achieved!"
        echo "✅ Build time improved by ${build_improvement_no_cache}%"
        echo "✅ Image size reduced by ${size_improvement}%"
        echo "✅ Cache efficiency at ${optimized_cache_efficiency}%"
    else
        log_warning "Some performance targets not met. Review optimization strategies."
    fi
    
    log_info "Detailed report saved to validation-report.json"
}

# Cleanup function
cleanup() {
    log_info "Cleaning up test images and logs..."
    docker images "${IMAGE_NAME}:test-*" --format "{{.Repository}}:{{.Tag}}" | xargs -r docker rmi > /dev/null 2>&1 || true
    docker images "${IMAGE_NAME}:baseline" --format "{{.Repository}}:{{.Tag}}" | xargs -r docker rmi > /dev/null 2>&1 || true
    docker images "${IMAGE_NAME}:optimized" --format "{{.Repository}}:{{.Tag}}" | xargs -r docker rmi > /dev/null 2>&1 || true
    rm -f /tmp/build-*.log /tmp/size-build.log
}

# Check prerequisites
check_prerequisites() {
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed"
        exit 1
    fi
    
    if ! command -v bc &> /dev/null; then
        log_error "bc calculator is not installed"
        exit 1
    fi
    
    if ! docker buildx version &> /dev/null; then
        log_error "Docker Buildx is not available"
        exit 1
    fi
}

# Main execution
main() {
    check_prerequisites
    trap cleanup EXIT
    
    case "${1:-validate}" in
        validate)
            run_validation
            ;;
        cleanup)
            cleanup
            ;;
        *)
            echo "Usage: $0 {validate|cleanup}"
            exit 1
            ;;
    esac
}

main "$@"