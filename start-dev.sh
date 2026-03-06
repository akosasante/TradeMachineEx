#!/bin/bash
# TradeMachineEx Development Startup Script

# Parse command line arguments
SKIP_INFRASTRUCTURE=false
RESTART=false
for arg in "$@"; do
    case $arg in
        --skip-infrastructure)
            SKIP_INFRASTRUCTURE=true
            shift
            ;;
        --restart)
            RESTART=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [--skip-infrastructure] [--restart] [--help]"
            echo ""
            echo "Options:"
            echo "  --skip-infrastructure  Skip starting PostgreSQL and Redis containers"
            echo "  --restart              Stop TradeMachineEx container before starting"
            echo "  -h, --help            Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $arg"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

echo "🚀 Starting TradeMachine Development Environment"
echo ""

# Check if we're in the right directory
if [ ! -f "mix.exs" ]; then
    echo "❌ Error: Please run this script from the TradeMachineEx directory"
    exit 1
fi

# Step 0: Optionally stop existing TradeMachineEx container
if [ "$RESTART" = true ]; then
    echo "🔄 Stopping existing TradeMachineEx container..."
    docker compose down
    if [ $? -eq 0 ]; then
        echo "✅ Container stopped"
    else
        echo "⚠️  No container to stop or error occurred"
    fi
    echo ""
fi

# Step 1: Start shared infrastructure (unless skipped)
if [ "$SKIP_INFRASTRUCTURE" = false ]; then
    echo "📡 Starting shared infrastructure (PostgreSQL, Redis)..."
    cd ..
    if [ ! -f "docker-compose.shared.yml" ]; then
        echo "❌ Error: docker-compose.shared.yml not found in parent directory"
        echo "   Make sure you're in the correct TradeMachine project structure"
        exit 1
    fi

    docker-compose -f docker-compose.shared.yml up -d
    if [ $? -ne 0 ]; then
        echo "❌ Failed to start shared infrastructure"
        exit 1
    fi

    echo "✅ Shared infrastructure started"
    echo ""
    cd TradeMachineEx
else
    echo "⏭️  Skipping infrastructure setup (PostgreSQL, Redis)"
    echo "   Make sure they're already running or available"
    echo ""
fi

# Step 2: Setup environment
echo "⚙️  Setting up TradeMachineEx environment..."

if [ ! -f ".env" ]; then
    echo "📄 Creating .env from template..."
    cp .env.development .env
    echo "✅ Created .env file (customize as needed)"
else
    echo "✅ .env file already exists"
fi

# Step 3: Get current Git SHA for metrics
echo "🔍 Getting current Git commit SHA..."
GIT_SHA=$(git rev-parse HEAD)
if [ $? -eq 0 ]; then
    export GIT_SHA
    echo "✅ Git SHA: ${GIT_SHA:0:8}... (exported for PromEx metrics)"
else
    echo "⚠️  Could not get Git SHA (not in a git repo?)"
    export GIT_SHA="unknown"
fi

# Load environment variables to display actual connection info
if [ -f ".env" ]; then
    # Source the env file (handle both export and non-export formats)
    set -a
    source .env
    set +a
fi

# Display actual connection details from env vars
PROD_DB_HOST=${PROD_DATABASE_HOST:-${DATABASE_HOST:-localhost}}
PROD_DB_PORT=${PROD_DATABASE_PORT:-${DATABASE_PORT:-5438}}
STAGING_DB_HOST=${STAGING_DATABASE_HOST:-${DATABASE_HOST:-localhost}}
STAGING_DB_PORT=${STAGING_DATABASE_PORT:-${DATABASE_PORT:-5438}}
PROD_SCHEMA=${PROD_SCHEMA:-dev}
STAGING_SCHEMA=${STAGING_SCHEMA:-dev}

# Step 4: Start TradeMachineEx
echo ""
echo "🏗️  Starting TradeMachineEx application..."
echo "   Connect to shared Postgres: "
echo "      Production DB: ${PROD_DB_HOST}:${PROD_DB_PORT} (schema: ${PROD_SCHEMA})"
echo "      Staging DB: ${STAGING_DB_HOST}:${STAGING_DB_PORT} (schema: ${STAGING_SCHEMA})"
echo "   Connect to shared Redis: localhost:6379"
echo "   TradeMachineEx app: localhost:4000"
echo "   Metrics endpoint: localhost:4000/metrics"
echo ""

docker compose up -d