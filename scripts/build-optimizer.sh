#!/bin/bash
# Docker Build Optimizer Script
# Implements advanced BuildKit features and caching strategies

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
REGISTRY="${REGISTRY:-ghcr.io}"
IMAGE_NAME="${IMAGE_NAME:-myapp}"
BUILD_PLATFORMS="${BUILD_PLATFORMS:-linux/amd64,linux/arm64}"
ENABLE_SBOM="${ENABLE_SBOM:-true}"
ENABLE_PROVENANCE="${ENABLE_PROVENANCE:-true}"

# Function to print colored output
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed"
        exit 1
    fi
    
    if ! docker buildx version &> /dev/null; then
        log_warning "Docker Buildx not found, installing..."
        docker buildx install
    fi
    
    log_success "Prerequisites check passed"
}

# Setup BuildKit builder with optimizations
setup_buildkit() {
    log_info "Setting up optimized BuildKit builder..."
    
    # Create builder with custom config
    docker buildx create --name optimized-builder \
        --driver docker-container \
        --driver-opt network=host \
        --driver-opt image=moby/buildkit:v0.12.0 \
        --config /dev/stdin <<EOF
[worker.oci]
  max-parallelism = 4
  
[registry."docker.io"]
  mirrors = ["mirror.gcr.io"]
  
[registry."${REGISTRY}"]
  insecure = false
  ca = ["/etc/ssl/certs/ca-certificates.crt"]
EOF
    
    docker buildx use optimized-builder
    docker buildx inspect --bootstrap
    
    log_success "BuildKit builder configured"
}

# Analyze Dockerfile for optimization opportunities
analyze_dockerfile() {
    local dockerfile="${1:-Dockerfile}"
    log_info "Analyzing $dockerfile for optimization opportunities..."
    
    local issues=0
    
    # Check for multiple RUN commands that could be combined
    if grep -c "^RUN" "$dockerfile" > 5; then
        log_warning "Multiple RUN commands detected. Consider combining to reduce layers."
        ((issues++))
    fi
    
    # Check for COPY before RUN commands (cache invalidation)
    if grep -B2 "^RUN.*install" "$dockerfile" | grep -q "^COPY"; then
        log_warning "COPY before package installation detected. This may invalidate cache."
        ((issues++))
    fi
    
    # Check for missing .dockerignore
    if [ ! -f ".dockerignore" ]; then
        log_warning "No .dockerignore file found. This may increase context size."
        ((issues++))
    fi
    
    # Check for apt-get without cleanup
    if grep "apt-get install" "$dockerfile" | grep -v "rm -rf /var/lib/apt/lists"; then
        log_warning "apt-get install without cleanup detected. Add cleanup to reduce image size."
        ((issues++))
    fi
    
    if [ $issues -eq 0 ]; then
        log_success "No major optimization issues found"
    else
        log_warning "Found $issues optimization opportunities"
    fi
}

# Build with advanced caching and optimization
build_optimized() {
    local dockerfile="${1:-src/Dockerfile.optimized}"
    local tag="${2:-latest}"
    
    log_info "Starting optimized build..."
    
    # Calculate build context size
    local context_size=$(du -sh . | cut -f1)
    log_info "Build context size: $context_size"
    
    # Build with all optimizations
    docker buildx build \
        --platform="${BUILD_PLATFORMS}" \
        --tag "${REGISTRY}/${IMAGE_NAME}:${tag}" \
        --tag "${REGISTRY}/${IMAGE_NAME}:cache" \
        --cache-from "type=gha" \
        --cache-from "type=registry,ref=${REGISTRY}/${IMAGE_NAME}:cache" \
        --cache-from "type=registry,ref=${REGISTRY}/${IMAGE_NAME}:latest" \
        --cache-to "type=gha,mode=max" \
        --cache-to "type=registry,ref=${REGISTRY}/${IMAGE_NAME}:cache,mode=max" \
        --metadata "org.opencontainers.image.source=https://github.com/${GITHUB_REPOSITORY}" \
        --metadata "org.opencontainers.image.revision=${GITHUB_SHA:-local}" \
        --sbom="${ENABLE_SBOM}" \
        --provenance="${ENABLE_PROVENANCE}" \
        --progress=plain \
        --file "${dockerfile}" \
        --push \
        .
    
    log_success "Build completed successfully"
}

# Measure build performance
measure_performance() {
    log_info "Measuring build performance..."
    
    local start_time=$(date +%s)
    
    # Perform test build without cache
    docker buildx build \
        --platform="linux/amd64" \
        --no-cache \
        --progress=plain \
        --file "src/Dockerfile.optimized" \
        . 2>&1 | tee /tmp/build-no-cache.log
    
    local no_cache_time=$(($(date +%s) - start_time))
    
    # Perform test build with cache
    start_time=$(date +%s)
    docker buildx build \
        --platform="linux/amd64" \
        --cache-from "type=registry,ref=${REGISTRY}/${IMAGE_NAME}:cache" \
        --progress=plain \
        --file "src/Dockerfile.optimized" \
        . 2>&1 | tee /tmp/build-with-cache.log
    
    local cache_time=$(($(date +%s) - start_time))
    
    # Calculate improvement
    local improvement=$(( (no_cache_time - cache_time) * 100 / no_cache_time ))
    
    log_info "Build time without cache: ${no_cache_time}s"
    log_info "Build time with cache: ${cache_time}s"
    log_success "Performance improvement: ${improvement}%"
    
    # Generate report
    cat > performance-report.json <<EOF
{
    "timestamp": "$(date -Iseconds)",
    "no_cache_build_time": ${no_cache_time},
    "cached_build_time": ${cache_time},
    "improvement_percentage": ${improvement},
    "platforms": "${BUILD_PLATFORMS}",
    "registry": "${REGISTRY}",
    "image": "${IMAGE_NAME}"
}
EOF
    
    log_success "Performance report saved to performance-report.json"
}

# Clean up resources
cleanup() {
    log_info "Cleaning up resources..."
    docker buildx rm optimized-builder 2>/dev/null || true
    docker system prune -f
    log_success "Cleanup completed"
}

# Main execution
main() {
    case "${1:-build}" in
        analyze)
            analyze_dockerfile "${2:-Dockerfile}"
            ;;
        setup)
            check_prerequisites
            setup_buildkit
            ;;
        build)
            check_prerequisites
            setup_buildkit
            analyze_dockerfile
            build_optimized
            ;;
        measure)
            check_prerequisites
            setup_buildkit
            measure_performance
            ;;
        cleanup)
            cleanup
            ;;
        *)
            echo "Usage: $0 {analyze|setup|build|measure|cleanup}"
            exit 1
            ;;
    esac
}

# Trap cleanup on exit
trap cleanup EXIT

# Run main function
main "$@"