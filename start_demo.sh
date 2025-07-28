#!/bin/bash

# Enhanced Authentication System Demo Startup Script
# Starts Keycloak, sets up Token Exchange V2, and launches all services

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

source "$SCRIPT_DIR/scripts/demo_utils.sh"

# Default environment variables
export MCP_SERVER_URI=${MCP_SERVER_URI:-http://localhost:8001}
export LLAMA_STACK_URL=${LLAMA_STACK_URL:-http://localhost:8321}
export ADMIN_EMAIL=${ADMIN_EMAIL:-}
export FLASK_SECRET_KEY=${FLASK_SECRET_KEY:-"dev-secret-change-in-production"}

export KEYCLOAK_IMAGE=${KEYCLOAK_IMAGE:-"quay.io/keycloak/keycloak:26.2"}

echo -e "${BLUE}🚀 Starting Token Exchange V2 Authentication Demo${NC}"
echo "===================================================="

echo -e "${BLUE}📋 Initial Configuration:${NC}"
echo "   MCP Server:     $MCP_SERVER_URI"
echo "   Llama Stack:    $LLAMA_STACK_URL"
echo "   Admin Email:    ${ADMIN_EMAIL:-Not set}"
echo "   Keycloak:      $KEYCLOAK_URL"
echo "   Architecture:   Single Client Token Exchange V2"

# Create logs directory
mkdir -p logs

# Clean up any existing Keycloak container
if [ "$KEYCLOAK_RUN_CONTAINER" = true ] ; then
    echo -e "${BLUE}🧹 Cleaning up existing Keycloak container...${NC}"
    if $CONTAINER_RUNTIME ps -a --format '{{.Names}}' | grep -q "^${KEYCLOAK_CONTAINER}$"; then
        $CONTAINER_RUNTIME stop $KEYCLOAK_CONTAINER >/dev/null 2>&1 || true
        $CONTAINER_RUNTIME rm $KEYCLOAK_CONTAINER >/dev/null 2>&1 || true
        echo -e "${GREEN}✅ Cleaned up existing container${NC}"
    fi
fi

# Function to cleanup everything
cleanup() {
    echo ""
    echo -e "${BLUE}🛑 Shutting down services...${NC}"
    
    # Kill background processes
    if [ ! -z "$ADMIN_PID" ]; then
        kill $ADMIN_PID 2>/dev/null || true
        echo "   ✅ Admin dashboard stopped"
    fi
    
    if [ ! -z "$MCP_PID" ]; then
        kill $MCP_PID 2>/dev/null || true
        echo "   ✅ MCP server stopped"
    fi
    
    if [ ! -z "$LLAMA_PID" ]; then
        kill $LLAMA_PID 2>/dev/null || true
        echo "   ✅ Llama Stack stopped"
    fi
    
    if [ ! -z "$FRONTEND_PID" ]; then
        kill $FRONTEND_PID 2>/dev/null || true
        echo "   ✅ Frontend stopped"
    fi
    
    # Stop Keycloak container
    if [ "$KEYCLOAK_RUN_CONTAINER" = true ] ; then
        if $CONTAINER_RUNTIME ps -q -f name=$KEYCLOAK_CONTAINER | grep -q .; then
            echo -e "${BLUE}🔐 Stopping Keycloak...${NC}"
            $CONTAINER_RUNTIME stop $KEYCLOAK_CONTAINER_NAME >/dev/null
            echo "   ✅ Keycloak stopped"
        fi
    fi

    echo -e "${GREEN}🏁 Demo stopped${NC}"
    exit 0
}

# Set up signal handlers
trap cleanup SIGINT SIGTERM

# Check if container runtime is active
if [ "$KEYCLOAK_RUN_CONTAINER" = true ] ; then
    if ! $CONTAINER_RUNTIME info > /dev/null 2>&1; then
        echo -e "${RED}❌ $CONTAINER_RUNTIME is not running. Please start $CONTAINER_RUNTIME and try again.${NC}"
        exit 1
    fi
fi

# Check for required dependencies
echo -e "${BLUE}🔍 Checking dependencies...${NC}"
if ! command -v python3 >/dev/null 2>&1; then
    echo -e "${RED}❌ Python 3 is required but not installed${NC}"
    exit 1
fi

if ! python3 -c "import requests" >/dev/null 2>&1; then
    echo -e "${YELLOW}⚠️  Installing required Python packages...${NC}"
    pip install requests
fi

echo -e "${GREEN}✅ Dependencies checked${NC}"

if [ "$KEYCLOAK_RUN_CONTAINER" = true ] ; then
    # Start Keycloak
    echo -e "\n${BLUE}🔐 Starting Keycloak with Token Exchange V2...${NC}"

    # Pull Keycloak image first
    echo "📥 Pulling Keycloak image..."
    $CONTAINER_RUNTIME pull $KEYCLOAK_IMAGE

    # Start Keycloak (Token Exchange V2 is enabled by default)
    $CONTAINER_RUNTIME run -d --name $KEYCLOAK_CONTAINER_NAME \
        -p $KEYCLOAK_PORT:8080 \
        -v keycloak_data:/opt/keycloak/data \
        -e KC_BOOTSTRAP_ADMIN_USERNAME=$KEYCLOAK_ADMIN \
        -e KC_BOOTSTRAP_ADMIN_PASSWORD=$KEYCLOAK_ADMIN_PASSWORD \
        $KEYCLOAK_IMAGE \
        start-dev

    # Wait for Keycloak to be ready
    echo -e "\n${BLUE}⏳ Waiting for Keycloak to start (this may take a minute)...${NC}"
    timeout=120
    counter=0
    while ! curl -s ${KEYCLOAK_URL}/health/ready >/dev/null 2>&1; do
        if [ $counter -eq $timeout ]; then
            echo -e "${RED}❌ Timeout waiting for Keycloak to start${NC}"
            cleanup
            exit 1
        fi
        if [ $((counter % 10)) -eq 0 ]; then
            echo -e "${YELLOW}   Still waiting for Keycloak... ($counter seconds)${NC}"
        fi
        sleep 2
        counter=$((counter + 2))
    done

    echo -e "${GREEN}✅ Keycloak is running!${NC}"

    # Give Keycloak a moment to fully initialize
    echo -e "${BLUE}⏳ Waiting for Keycloak to fully initialize...${NC}"
    sleep 10
fi

# Test admin API access
echo -e "${BLUE}🔍 Testing Keycloak admin API access...${NC}"
ADMIN_TOKEN_RESPONSE=$(curl -s -X POST \
    -d "client_id=admin-cli" \
    -d "username=$KEYCLOAK_ADMIN" \
    -d "password=$KEYCLOAK_ADMIN_PASSWORD" \
    -d "grant_type=password" \
    "${KEYCLOAK_URL}/realms/master/protocol/openid-connect/token")

if ! echo "$ADMIN_TOKEN_RESPONSE" | grep -q "access_token"; then
    echo -e "${RED}❌ Could not get admin token. Response:${NC}"
    echo "$ADMIN_TOKEN_RESPONSE"
    echo -e "${YELLOW}💡 Keycloak might need more time to initialize. Waiting another 10 seconds...${NC}"
    sleep 10
fi

# Run Token Exchange V2 setup script
echo -e "\n${BLUE}🔧 Setting up complete Token Exchange V2 configuration...${NC}"
echo -e "${YELLOW}📋 This will configure:${NC}"
echo "   • Realm with Token Exchange V2 enabled"
echo "   • Confidential client with self-exchange"
echo "   • Custom scopes (MCP + Llama Stack)"
echo "   • Role-based authorization policies"
echo "   • Test users with proper role assignments"
echo ""

# Create a temporary file for the output
SETUP_OUTPUT_FILE=$(mktemp)

# Run Token Exchange V2 setup and show output in real-time while also capturing it
python setup_keycloak_v2.py 2>&1 | tee "$SETUP_OUTPUT_FILE"
SETUP_STATUS=${PIPESTATUS[0]}

# Check if setup failed
if [ $SETUP_STATUS -ne 0 ]; then
    echo -e "${RED}❌ Token Exchange V2 setup failed with status $SETUP_STATUS${NC}"

    if [ "$KEYCLOAK_RUN_CONTAINER" = true ] ; then
        echo -e "${YELLOW}💡 Checking Keycloak container logs:${NC}"
        $CONTAINER_RUNTIME logs $KEYCLOAK_CONTAINER_NAME
    fi

    echo -e "${YELLOW}💡 Check the errors above and try:${NC}"
    echo "   1. Run cleanup_demo.sh and start fresh"

    if [ "$KEYCLOAK_RUN_CONTAINER" = true ] ; then
        echo "   2. Check Keycloak logs: $CONTAINER_RUNTIME logs $KEYCLOAK_CONTAINER_NAME"
        echo "   3. Ensure no port conflicts on $KEYCLOAK_POST"
    fi

    rm -f "$SETUP_OUTPUT_FILE"
    cleanup
    exit 1
fi

# Clean up temporary file
rm -f "$SETUP_OUTPUT_FILE"

echo -e "\n${GREEN}✅ Token Exchange V2 setup complete!${NC}"

# Set and display OIDC configuration after successful setup
echo -e "\n${BLUE}🔧 Setting OIDC Configuration...${NC}"
export OIDC_CLIENT_SECRET="demo-client-secret-change-in-production"

# Create a .env file with OIDC configuration
cat > $SCRIPT_DIR/frontends/chat-ui/.env << EOF
# OIDC Configuration (Generated by Token Exchange V2 setup)
OIDC_ISSUER_URL=${OIDC_ISSUER_URL}
OIDC_CLIENT_ID=${OIDC_CLIENT_ID}
OIDC_CLIENT_SECRET=${OIDC_CLIENT_SECRET}

ADMIN_EMAIL="aguclu@redhat.com"

# Flask Configuration
FLASK_SECRET_KEY=${FLASK_SECRET_KEY}
FLASK_ENV=development

# Service URLs
LLAMA_STACK_URL=${LLAMA_STACK_URL}

# UI Configuration
CHAT_UI_PORT=5001
CHAT_UI_HOST=0.0.0.0
CHAT_UI_DEBUG=true
EOF

cat > $SCRIPT_DIR/frontends/admin-dashboard/.env << EOF
# OIDC Configuration (Generated by Token Exchange V2 setup)
OIDC_ISSUER_URL=${OIDC_ISSUER_URL}
OIDC_CLIENT_ID=${OIDC_CLIENT_ID}
OIDC_CLIENT_SECRET=${OIDC_CLIENT_SECRET}

ADMIN_EMAIL="aguclu@redhat.com"

# Flask Configuration
FLASK_SECRET_KEY=${FLASK_SECRET_KEY}
FLASK_ENV=development

# Service URLs
LLAMA_STACK_URL=${LLAMA_STACK_URL}

# UI Configuration
CHAT_UI_PORT=5001
CHAT_UI_HOST=0.0.0.0
CHAT_UI_DEBUG=true
EOF

# Also create a general .env file in the root
cat > .env << EOF
# OIDC Configuration (Generated by Token Exchange V2 setup)
OIDC_ISSUER_URL=${OIDC_ISSUER_URL}
OIDC_CLIENT_ID=${OIDC_CLIENT_ID}
OIDC_CLIENT_SECRET=${OIDC_CLIENT_SECRET}

ADMIN_EMAIL="aguclu@redhat.com"

# Service URLs
MCP_SERVER_URI=${MCP_SERVER_URI}
LLAMA_STACK_URL=${LLAMA_STACK_URL}

# Flask Configuration  
FLASK_SECRET_KEY=${FLASK_SECRET_KEY}
FLASK_ENV=development
EOF

# Source the .env file to load variables into current shell
echo -e "${BLUE}📥 Loading environment variables...${NC}"
set -a  # automatically export all variables
source .env
set +a  # turn off automatic export

echo -e "\n${GREEN}📋 OIDC Configuration Ready:${NC}"
echo "=============================================="
echo -e "${BLUE}Issuer URL:${NC}     $OIDC_ISSUER_URL"
echo -e "${BLUE}Client ID:${NC}      $OIDC_CLIENT_ID"
echo -e "${BLUE}Client Secret:${NC}  $OIDC_CLIENT_SECRET"
echo ""
echo -e "${GREEN}✅ Environment files created and loaded:${NC}"
echo "   📄 $SCRIPT_DIR/frontends/chat-ui/.env"
echo "   📄 $SCRIPT_DIR/.env (root directory)"
echo ""
echo -e "${GREEN}💡 Variables are now available in this shell session${NC}"
echo -e "${YELLOW}💡 For other terminals:${NC} source .env"
echo "=============================================="

# Run comprehensive Token Exchange V2 tests
echo -e "\n${BLUE}🧪 Running Token Exchange V2 validation tests...${NC}"
echo -e "${YELLOW}📋 This will validate:${NC}"
echo "   • User authentication with minimal scopes"
echo "   • Token exchange for service-specific scopes"
echo "   • Role-based access control enforcement"
echo "   • JWT token structure and claims"
echo "   • Self-exchange pattern functionality"
echo ""

if python $SCRIPT_DIR/test_token_exchange_v2.py; then
    echo -e "\n${GREEN}✅ Token Exchange V2 validation passed!${NC}"
    echo -e "${GREEN}✅ All authentication and authorization systems working correctly!${NC}"
else
    echo -e "\n${RED}❌ Token Exchange V2 validation failed${NC}"
    echo -e "${YELLOW}💡 Common issues:${NC}"
    echo "   1. Keycloak setup incomplete"
    echo "   2. Network connectivity issues"
    echo "   3. Authorization policies not configured properly"
    echo ""
    echo -e "${YELLOW}💡 To debug:${NC}"
    echo "   1. Check Keycloak logs: $CONTAINER_RUNTIME logs $KEYCLOAK_CONTAINER_NAME"
    echo "   2. Verify Keycloak admin console: ${KEYCLOAK_URL}/admin"
    echo "   3. Re-run setup: python $SCRIPT_DIR/setup_keycloak_v2.py"
    echo "   4. Re-run tests: python $SCRIPT_DIR/test_token_exchange_v2.py"
    echo ""
    echo -e "${BLUE}Press ENTER to continue anyway, or Ctrl+C to exit...${NC}"
    read -r
fi

# Load any additional environment variables from .env file
if [ -f ".env" ]; then
    echo -e "\n${BLUE}📋 Loading additional environment variables from .env file...${NC}"
    while IFS='=' read -r key value; do
        if [ ! -z "$key" ] && [ ! -z "$value" ] && [[ ! "$key" =~ ^# ]]; then
            # Don't override OIDC values from Token Exchange V2 setup
            if [[ ! "$key" =~ ^OIDC_ ]]; then
                export "$key"="$value"
                echo "   Updated: $key"
            fi
        fi
    done < .env
fi

# Validate required OIDC configuration
if [ -z "$OIDC_ISSUER_URL" ] || [ -z "$OIDC_CLIENT_ID" ] || [ -z "$OIDC_CLIENT_SECRET" ]; then
    echo -e "\n${RED}❌ ERROR: Missing required OIDC configuration!${NC}"
    echo "The following variables are required:"
    echo -e "   OIDC_ISSUER_URL:    ${OIDC_ISSUER_URL:-${RED}Not Set${NC}}"
    echo -e "   OIDC_CLIENT_ID:     ${OIDC_CLIENT_ID:-${RED}Not Set${NC}}"
    echo -e "   OIDC_CLIENT_SECRET: ${OIDC_CLIENT_SECRET:-${RED}Not Set${NC}}"
    echo ""
    echo -e "${YELLOW}💡 This usually means:${NC}"
    echo "   1. Token Exchange V2 setup failed to complete successfully"
    echo "   2. The .env file has incorrect OIDC configuration"
    echo ""
    echo "Try:"
    echo "   1. Running cleanup_demo.sh and starting fresh"
    echo "   2. Checking the Keycloak logs: $CONTAINER_RUNTIME logs $KEYCLOAK_CONTAINER"
    cleanup
    exit 1
fi

# Validate Keycloak is responding
echo -e "\n${BLUE}🔍 Validating Keycloak Token Exchange V2 configuration...${NC}"
if ! curl -s "$OIDC_ISSUER_URL/.well-known/openid-configuration" >/dev/null; then
    echo -e "${RED}❌ ERROR: Cannot connect to Keycloak at $OIDC_ISSUER_URL${NC}"
    echo "This usually means:"
    echo "   1. Keycloak is not running"
    echo "   2. The OIDC_ISSUER_URL is incorrect"
    echo ""
    echo "Try:"
    echo "   1. Checking if Keycloak is running: $CONTAINER_RUNTIME ps"
    echo "   2. Viewing Keycloak logs: $CONTAINER_RUNTIME logs $KEYCLOAK_CONTAINER"
    cleanup
    exit 1
fi

echo -e "${GREEN}✅ Token Exchange V2 configuration validated${NC}"

# Now start other services

# Start MCP Server
echo -e "\n${BLUE}🔧 Starting MCP Server...${NC}"

FASTMCP_PORT=8001 python "$SCRIPT_DIR/mcp/mcp_server.py" > "$SCRIPT_DIR/logs/mcp_server.log" 2>&1 &
MCP_PID=$!

echo "   ✅ MCP Server started (PID: $MCP_PID)"

# Start Admin Dashboard Frontend
echo -e "\n${BLUE}🎛️  Starting Admin Dashboard...${NC}"
python "$SCRIPT_DIR/frontends/admin-dashboard/app.py" > "$SCRIPT_DIR/logs/admin_dashboard.log" 2>&1 &
ADMIN_PID=$!
echo "   ✅ Admin Dashboard started (PID: $ADMIN_PID)"

# Start Llama Stack
echo -e "\n${BLUE}🦙 Starting Llama Stack...${NC}"
llama stack run "$SCRIPT_DIR/services/stack/run.yml" > "$SCRIPT_DIR/logs/llama_stack.log" 2>&1 &
LLAMA_PID=$!
echo "   ✅ Llama Stack started (PID: $LLAMA_PID)"

# Start Frontend
echo -e "\n${BLUE}🌐 Starting Frontend...${NC}"
python "$SCRIPT_DIR/frontends/chat-ui/app.py" > "$SCRIPT_DIR/logs/frontend.log" 2>&1 &
FRONTEND_PID=$!
echo "   ✅ Frontend started (PID: $FRONTEND_PID)"

# Wait for services to initialize
sleep 3

echo -e "\n${GREEN}🎉 Token Exchange V2 Demo is ready!${NC}"
echo "=================================================="
echo -e "${BLUE}📱 Access Points:${NC}"
echo "   🌐 Chat Frontend:    http://localhost:5001"
echo "   🎛️  Admin Dashboard: http://localhost:8003"
echo "   🔧 MCP Server:      http://localhost:8001"
echo "   🦙 Llama Stack:     http://localhost:8321"
echo "   🔐 Keycloak:        $KEYCLOAK_URL"
echo "   👑 Keycloak Admin:  $KEYCLOAK_URL/admin ($KEYCLOAK_ADMIN/$KEYCLOAK_ADMIN_PASSWORD)"

echo -e "\n${BLUE}📊 Monitoring:${NC}"
echo "   📝 View all logs:          tail -f logs/*.log"
echo "   📝 Admin Dashboard logs:   tail -f logs/admin_dashboard.log"
echo "   📝 MCP Server logs:        tail -f logs/mcp_server.log"
echo "   📝 Llama Stack logs:       tail -f logs/llama_stack.log"
echo "   📝 Frontend logs:          tail -f logs/frontend.log"
echo "   📝 Keycloak logs:          $CONTAINER_RUNTIME logs -f $KEYCLOAK_CONTAINER"

echo -e "\n${BLUE}🔐 Token Exchange V2 Features:${NC}"
echo -e "${GREEN}✅ Zero-Trust Architecture:${NC}"
echo "   • Users start with minimal scopes (openid, profile, email)"
echo "   • Dynamic scope upgrade via token exchange"
echo "   • Service-specific scope requests"
echo ""
echo -e "${GREEN}✅ Role-Based Access Control:${NC}"
echo "   • User role: MCP basic scopes + Llama operations"
echo "   • Admin role: Full system access including execute_command"
echo ""
echo -e "${GREEN}✅ Self-Exchange Pattern:${NC}"
echo "   • Single client: authentication-demo"
echo "   • Simplified architecture with fine-grained scopes"
echo "   • RFC 8693 compliant implementation"

echo -e "\n${BLUE}👥 Test Users:${NC}"
echo "   🙋‍♂️ lance (password: password) - User role"
echo "   👩‍💼 admin-user (password: password) - Admin role"

echo -e "\n${YELLOW}💡 Quick Start:${NC}"
echo "   1. Visit http://localhost:5001"
echo "   2. Log in with lance/password or admin-user/password"
echo "   3. Start chatting - tokens will be exchanged automatically!"

echo -e "\n${BLUE}🧪 Test Commands:${NC}"
echo "   • Re-run validation: python test_token_exchange_v2.py"
echo "   • Check configuration: python setup_keycloak_v2.py"

echo -e "\n${BLUE}🛑 To stop everything: Ctrl+C${NC}"
echo ""

# Wait for user interruption
wait 