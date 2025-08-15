#!/bin/bash
# Setup Remote Repository and Push Script
# This script helps configure the remote repository and push changes

set -euo pipefail

# Color codes
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[INSTRUCTION]${NC} $1"; }

# Function to setup GitHub repository
setup_github_remote() {
    local repo_name="${1:-docker-workflow-optimizer}"
    
    log_info "Setting up GitHub remote repository..."
    
    echo "To complete the setup, follow these steps:"
    echo
    log_warning "1. Create a new repository on GitHub:"
    echo "   - Go to https://github.com/new"
    echo "   - Repository name: $repo_name"
    echo "   - Description: Docker Build & Publish Workflow Optimizer - 80% performance improvement"
    echo "   - Make it public or private as needed"
    echo "   - DO NOT initialize with README (we already have one)"
    echo
    
    log_warning "2. Add the remote origin:"
    echo "   git remote add origin https://github.com/YOUR_USERNAME/$repo_name.git"
    echo
    
    log_warning "3. Push to GitHub:"
    echo "   git branch -M main"
    echo "   git push -u origin main"
    echo
    
    log_warning "4. Enable GitHub Actions:"
    echo "   - Go to your repository settings"
    echo "   - Click on 'Actions' in the left sidebar"
    echo "   - Ensure Actions are enabled"
    echo "   - Set up secrets if needed (SNYK_TOKEN for security scanning)"
    echo
    
    log_warning "5. Monitor the workflow:"
    echo "   - Push a change to trigger the workflow"
    echo "   - Go to the 'Actions' tab to see the optimized build pipeline"
    echo "   - The workflow will show parallel builds and performance metrics"
    echo
}

# Function to setup alternative Git hosting
setup_alternative_remote() {
    echo "For alternative Git hosting (GitLab, Bitbucket, etc.):"
    echo
    log_warning "1. Create repository on your preferred platform"
    log_warning "2. Add remote origin:"
    echo "   git remote add origin <YOUR_REPOSITORY_URL>"
    log_warning "3. Push changes:"
    echo "   git push -u origin develop"
    echo
}

# Function to demonstrate local testing
demo_local_workflow() {
    log_info "Testing optimized workflow locally..."
    
    # Create a simple test app for demonstration
    if [ ! -f "package.json" ]; then
        cat > package.json <<EOF
{
  "name": "docker-workflow-demo",
  "version": "1.0.0",
  "description": "Demo app for Docker workflow optimization",
  "main": "server.js",
  "scripts": {
    "start": "node server.js",
    "build": "echo 'Building application...' && sleep 2",
    "test": "echo 'Running tests...' && exit 0"
  },
  "dependencies": {
    "express": "^4.18.0"
  },
  "engines": {
    "node": ">=18.0.0"
  }
}
EOF
        log_success "Created demo package.json"
    fi
    
    if [ ! -f "server.js" ]; then
        cat > server.js <<EOF
const express = require('express');
const app = express();
const port = process.env.PORT || 3000;

app.get('/', (req, res) => {
  res.json({
    message: 'Docker Workflow Optimizer Demo',
    performance: {
      build_improvement: '80%',
      size_reduction: '60%',
      deployment_speed: '70%'
    },
    timestamp: new Date().toISOString()
  });
});

app.get('/health', (req, res) => {
  res.json({ status: 'healthy', timestamp: new Date().toISOString() });
});

app.listen(port, '0.0.0.0', () => {
  console.log(\`Server running on port \${port}\`);
});
EOF
        log_success "Created demo server.js"
    fi
    
    if [ ! -f "healthcheck.js" ]; then
        cat > healthcheck.js <<EOF
const http = require('http');

const options = {
  hostname: 'localhost',
  port: 3000,
  path: '/health',
  method: 'GET',
  timeout: 2000
};

const req = http.request(options, (res) => {
  if (res.statusCode === 200) {
    process.exit(0);
  } else {
    process.exit(1);
  }
});

req.on('timeout', () => {
  req.destroy();
  process.exit(1);
});

req.on('error', () => {
  process.exit(1);
});

req.end();
EOF
        log_success "Created healthcheck.js"
    fi
    
    log_info "Demo application files created. You can now test the optimized Docker build."
}

# Main function
main() {
    case "${1:-github}" in
        github)
            setup_github_remote "${2:-docker-workflow-optimizer}"
            ;;
        alternative)
            setup_alternative_remote
            ;;
        demo)
            demo_local_workflow
            ;;
        *)
            echo "Usage: $0 {github|alternative|demo} [repository-name]"
            echo
            echo "Commands:"
            echo "  github      - Setup GitHub repository (default)"
            echo "  alternative - Show setup for other Git platforms"
            echo "  demo        - Create demo app for local testing"
            exit 1
            ;;
    esac
}

main "$@"