#!/bin/bash

# Cloud Run deployment script using Docker build
# This script builds the Docker image first, then deploys to Cloud Run

set -e  # Exit on error

# Load .env file if it exists
if [ -f .env ]; then
    echo "Loading environment variables from .env file..."
    export $(grep -v '^#' .env | xargs)
fi

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration variables
SERVICE_NAME="ext-image-processing-api-handler"
REGION="${REGION:-us-central1}"
PLATFORM="managed"
MEMORY="1024Mi"
CPU="0.5833"
TIMEOUT="60"
CONCURRENCY="1"
MAX_INSTANCES="34"
HOSTNAME="${HOSTNAME:-xinjiangshao.com}"
# Function to print colored messages
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if gcloud is installed
if ! command -v gcloud &> /dev/null; then
    print_error "gcloud CLI is not installed. Please install it from: https://cloud.google.com/sdk/docs/install"
    exit 1
fi

# Check if docker is installed
if ! command -v docker &> /dev/null; then
    print_error "Docker is not installed. Please install it from: https://docs.docker.com/get-docker/"
    exit 1
fi

# Get GCP project ID
if [ -z "$GCLOUD_PROJECT" ]; then
    GCLOUD_PROJECT=$(gcloud config get-value project 2>/dev/null)
    if [ -z "$GCLOUD_PROJECT" ]; then
        print_error "No GCP project set. Please set it with: gcloud config set project PROJECT_ID"
        exit 1
    fi
fi

print_info "Using GCP Project: $GCLOUD_PROJECT"

# Get or prompt for Cloud Storage bucket
if [ -z "$CLOUD_STORAGE_BUCKET" ]; then
    print_warn "CLOUD_STORAGE_BUCKET not set"
    read -p "Enter your Cloud Storage bucket name (e.g., $GCLOUD_PROJECT.appspot.com): " CLOUD_STORAGE_BUCKET
    if [ -z "$CLOUD_STORAGE_BUCKET" ]; then
        print_error "Cloud Storage bucket name is required"
        exit 1
    fi
fi

# Set CORS origin allow list (default to *)
CORS_ORIGIN_ALLOW_LIST="${CORS_ORIGIN_ALLOW_LIST:-*}"

# Set image repository and tag
IMAGE_REPO="gcr.io/$GCLOUD_PROJECT/$SERVICE_NAME"
IMAGE_TAG="${IMAGE_TAG:-latest}"
FULL_IMAGE="$IMAGE_REPO:$IMAGE_TAG"

# Optional: Service account
if [ -n "$SERVICE_ACCOUNT" ]; then
    SERVICE_ACCOUNT_FLAG="--service-account=$SERVICE_ACCOUNT"
else
    SERVICE_ACCOUNT_FLAG=""
fi

# Optional: Allow unauthenticated
if [ "$ALLOW_UNAUTHENTICATED" = "true" ]; then
    AUTH_FLAG="--allow-unauthenticated"
else
    AUTH_FLAG="--no-allow-unauthenticated"
fi

print_info "Deployment Configuration:"
echo "  Service Name: $SERVICE_NAME"
echo "  Region: $REGION"
echo "  Memory: $MEMORY"
echo "  CPU: $CPU"
echo "  Timeout: ${TIMEOUT}s"
echo "  Concurrency: $CONCURRENCY"
echo "  Max Instances: $MAX_INSTANCES"
echo "  Cloud Storage Bucket: $CLOUD_STORAGE_BUCKET"
echo "  CORS Allow List: $CORS_ORIGIN_ALLOW_LIST"
echo "  Docker Image: $FULL_IMAGE"

# Confirm deployment
read -p "$(echo -e ${YELLOW}Proceed with build and deployment? [y/N]:${NC} )" -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_warn "Deployment cancelled"
    exit 0
fi

# Configure Docker authentication for GCR
print_info "Configuring Docker authentication for GCR..."
gcloud auth configure-docker --quiet

# Build Docker image for AMD64 (Cloud Run architecture)
print_info "Building Docker image for AMD64 platform: $FULL_IMAGE"
docker build --platform linux/amd64 -t "$FULL_IMAGE" .

if [ $? -ne 0 ]; then
    print_error "Docker build failed"
    exit 1
fi

# Push image to GCR
print_info "Pushing image to Google Container Registry..."
docker push "$FULL_IMAGE"

if [ $? -ne 0 ]; then
    print_error "Docker push failed"
    exit 1
fi

print_info "Deploying to Cloud Run..."

# Deploy to Cloud Run
gcloud run deploy "$SERVICE_NAME" \
  --image "$FULL_IMAGE" \
  --platform "$PLATFORM" \
  --region "$REGION" \
  --memory "$MEMORY" \
  --cpu "$CPU" \
  --timeout "$TIMEOUT" \
  --concurrency "$CONCURRENCY" \
  --max-instances "$MAX_INSTANCES" \
  --set-env-vars "GCLOUD_PROJECT=$GCLOUD_PROJECT,PROJECT_ID=$GCLOUD_PROJECT,CLOUD_STORAGE_BUCKET=$CLOUD_STORAGE_BUCKET,STORAGE_BUCKET=$CLOUD_STORAGE_BUCKET,CORS_ORIGIN_ALLOW_LIST=$CORS_ORIGIN_ALLOW_LIST,LOCATION=$REGION,FUNCTION_SIGNATURE_TYPE=http,NODE_ENV=production,HOSTNAME=$HOSTNAME" \
  $SERVICE_ACCOUNT_FLAG \
  $AUTH_FLAG

if [ $? -eq 0 ]; then
    print_info "Deployment successful!"

    # Get the service URL
    SERVICE_URL=$(gcloud run services describe "$SERVICE_NAME" --region "$REGION" --format='value(status.url)')

    print_info "Service URL: $SERVICE_URL"
    print_info "Health check: $SERVICE_URL/health"

    echo ""
    print_info "Test the API with:"
    echo "  curl $SERVICE_URL/health"
else
    print_error "Deployment failed"
    exit 1
fi
