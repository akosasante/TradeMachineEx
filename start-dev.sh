#!/bin/bash
# TradeMachineEx Development Startup Script

echo "🚀 Starting TradeMachine Development Environment"
echo ""

# Check if we're in the right directory
if [ ! -f "mix.exs" ]; then
    echo "❌ Error: Please run this script from the TradeMachineEx directory"
    exit 1
fi

# Step 1: Start shared infrastructure
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

# Step 2: Setup environment
cd TradeMachineEx
echo "⚙️  Setting up TradeMachineEx environment..."

if [ ! -f ".env" ]; then
    echo "📄 Creating .env from template..."
    cp .env.development .env
    echo "✅ Created .env file (customize as needed)"
else
    echo "✅ .env file already exists"
fi

# Step 3: Start TradeMachineEx
echo ""
echo "🏗️  Starting TradeMachineEx application..."
echo "   Connect to shared Postgres: localhost:5438"
echo "   Connect to shared Redis: localhost:6379"
echo "   TradeMachineEx app: localhost:4000"
echo ""

docker-compose up