#!/bin/bash

# 🧹 Token Exchange V2 Demo Cleanup Script
# Removes all demo data for a fresh start

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

source "$SCRIPT_DIR/scripts/demo_utils.sh"

echo -e "${BLUE}🧹 Token Exchange V2 Demo Cleanup${NC}"
echo "====================================="
echo ""
echo -e "${YELLOW}⚠️  WARNING: This will delete ALL Token Exchange V2 demo data:${NC}"
echo "   - Keycloak realm and configuration"
echo "   - Database (users, permissions, approvals)"
echo "   - JWT keys (will be regenerated on next start)"
echo "   - Log files"
echo "   - Session data"
echo "   - Browser cookies"
echo ""

# Ask for confirmation
read -p "Are you sure you want to proceed? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}❌ Cleanup cancelled${NC}"
    exit 0
fi

echo ""
echo -e "${BLUE}🛑 Stopping all demo services first...${NC}"

# Stop services first
$SCRIPT_DIR/stop_demo.sh > /dev/null 2>&1 || true

echo ""
echo -e "${BLUE}🗑️  Cleaning up demo artifacts...${NC}"

# Function to safely remove file/directory
safe_remove() {
    local path=$1
    local description=$2
    
    if [ -e "$path" ]; then
        rm -rf "$path"
        echo -e "${GREEN}✅ Removed $description${NC}"
    else
        echo -e "${YELLOW}⚠️  $description not found (already clean)${NC}"
    fi
}

if [ "$KEYCLOAK_RUN_CONTAINER" = true ] ; then
    # Clean up Keycloak
    echo ""
    echo -e "${YELLOW}🔐 Keycloak Token Exchange V2 cleanup:${NC}"
    if $CONTAINER_RUNTIME ps -a -q -f name=$KEYCLOAK_CONTAINER_NAME | grep -q .; then
        echo -e "${YELLOW}🔄 Removing Keycloak container...${NC}"
        $CONTAINER_RUNTIME rm -f $KEYCLOAK_CONTAINER_NAME >/dev/null 2>&1
        echo -e "${GREEN}✅ Keycloak container removed${NC}"
    else
        echo -e "${YELLOW}⚠️  Keycloak container not found (already clean)${NC}"
    fi

    # Clean up Keycloak data volumes
    echo -e "${YELLOW}🔄 Removing Keycloak data volume...${NC}"
    if $CONTAINER_RUNTIME volume ls -q | grep -q "$KEYCLOAK_VOLUME_NAME"; then
        $CONTAINER_RUNTIME volume rm "$KEYCLOAK_VOLUME_NAME" >/dev/null 2>&1 || true
        echo -e "${GREEN}✅ Removed Keycloak data volume${NC}"
    else
        echo -e "${YELLOW}⚠️  Keycloak data volume not found (already clean)${NC}"
    fi

    # Clean up any other keycloak-related volumes
    $CONTAINER_RUNTIME volume ls -q -f name=$KEYCLOAK_CONTAINER_NAME | while read volume; do
        if [ ! -z "$volume" ]; then
            $CONTAINER_RUNTIME volume rm "$volume" >/dev/null 2>&1 || true
            echo -e "${GREEN}✅ Removed volume: $volume${NC}"
        fi
    done

    # Also remove any unnamed volumes that might be from Keycloak
    echo -e "${YELLOW}🔄 Cleaning up dangling volumes...${NC}"
    $CONTAINER_RUNTIME volume prune -f >/dev/null 2>&1 || true
    echo -e "${GREEN}✅ Cleaned up dangling volumes${NC}"
fi

# Clean up databases
echo ""
echo -e "${YELLOW}📊 Database cleanup:${NC}"
safe_remove "$SCRIPT_DIR/auth-server/auth.db" "auth database"
safe_remove "$SCRIPT_DIR/auth.db" "auth database (root)"
safe_remove "$SCRIPT_DIR/responses.db" "responses database"
safe_remove "$SCRIPT_DIR/kvstore.db" "key-value store database"

# Clean up JWT keys
echo ""
echo -e "${YELLOW}🔑 JWT keys cleanup:${NC}"
safe_remove "$SCRIPT_DIR/auth-server/keys/" "JWT keys directory"

# Clean up logs
echo ""
echo -e "${YELLOW}📝 Log files cleanup:${NC}"
safe_remove "$SCRIPT_DIR/logs/" "logs directory"
safe_remove "$SCRIPT_DIR/cookies.txt" "HTTP cookies file"

# Clean up session/cache files
echo ""
echo -e "${YELLOW}💾 Session/cache cleanup:${NC}"
safe_remove "$SCRIPT_DIR/demo_pids.txt" "process IDs file"
safe_remove "$SCRIPT_DIR/__pycache__/" "Python cache (root)"
safe_remove "$SCRIPT_DIR/auth-server/__pycache__/" "Python cache (auth-server)"
safe_remove "$SCRIPT_DIR/frontends/__pycache__/" "Python cache (frontends)"
safe_remove "$SCRIPT_DIR/frontends/chat-ui/__pycache__/" "Python cache (chat-ui)"
safe_remove "$SCRIPT_DIR/frontends/admin-dashboard/__pycache__/" "Python cache (admin-dashboard)"
safe_remove "$SCRIPT_DIR/mcp/__pycache__/" "Python cache (mcp)"
safe_remove "$SCRIPT_DIR/services/__pycache__/" "Python cache (services)"

# Clean up Python egg-info and build artifacts
echo ""
echo -e "${YELLOW}🥚 Python package artifacts:${NC}"
safe_remove "$SCRIPT_DIR/services/auth-agent/src/auth_agent.egg-info/" "auth-agent egg-info"
safe_remove "$SCRIPT_DIR/services/auth-agent/build/" "auth-agent build"
safe_remove "$SCRIPT_DIR/services/auth-agent/dist/" "auth-agent dist"

# Clean up any .pyc files
echo ""
echo -e "${YELLOW}🐍 Python bytecode cleanup:${NC}"
find . -name "*.pyc" -delete 2>/dev/null || true
find . -name "*.pyo" -delete 2>/dev/null || true
find . -name "*.pyd" -delete 2>/dev/null || true
echo -e "${GREEN}✅ Removed Python bytecode files${NC}"

# Clean up environment-specific files
echo ""
echo -e "${YELLOW}🌍 Environment cleanup:${NC}"
safe_remove ".env.local" "local environment file"
echo -e "${YELLOW}⚠️  Preserving virtual environment directory (env/)${NC}"

# Chrome cookies cleanup
echo ""
echo -e "${YELLOW}🍪 Browser cookies cleanup:${NC}"

cleanup_chrome_cookies() {
    # Force quit Chrome first
    echo -e "${YELLOW}🔄 Force closing Chrome...${NC}"
    pkill -f "Google Chrome" 2>/dev/null || true
    sleep 2
    
    # Determine Chrome cookies path based on OS
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS Chrome cookies
        CHROME_COOKIES="$HOME/Library/Application Support/Google/Chrome/Default/Cookies"
    else
        # Linux Chrome cookies
        CHROME_COOKIES="$HOME/.config/google-chrome/Default/Cookies"
    fi
    
    # Clear Chrome localhost cookies
    if [ -f "$CHROME_COOKIES" ] && command -v sqlite3 >/dev/null 2>&1; then
        echo -e "${YELLOW}🔄 Clearing Chrome localhost cookies...${NC}"
        sqlite3 "$CHROME_COOKIES" "DELETE FROM cookies WHERE host_key LIKE '%localhost%' OR host_key LIKE '%.localhost%';" 2>/dev/null || true
        echo -e "${GREEN}✅ Chrome localhost cookies cleared${NC}"
    else
        echo -e "${YELLOW}⚠️  Chrome cookies database not found or sqlite3 not available${NC}"
    fi
}

#cleanup_chrome_cookies

# Clean up any remaining demo processes
echo ""
echo -e "${YELLOW}⚡ Process cleanup:${NC}"
REMAINING_PIDS=$(ps aux | grep -E "(auth_server|unified_auth_server|mcp_server|chat_app|admin_dashboard)" | grep -v grep | awk '{print $2}' || true)

if [ -n "$REMAINING_PIDS" ]; then
    echo -e "${YELLOW}🔄 Killing remaining demo processes...${NC}"
    echo "$REMAINING_PIDS" | xargs kill -9 2>/dev/null || true
    echo -e "${GREEN}✅ Cleaned up remaining processes${NC}"
else
    echo -e "${GREEN}✅ No demo processes running${NC}"
fi

# Verify cleanup
echo ""
echo -e "${BLUE}🔍 Cleanup verification:${NC}"

verify_clean() {
    local path=$1
    local name=$2
    
    if [ -e "$path" ]; then
        echo -e "${RED}❌ $name still exists: $path${NC}"
        return 1
    else
        echo -e "${GREEN}✅ $name cleaned${NC}"
        return 0
    fi
}

verify_clean "$SCRIPT_DIR/auth-server/auth.db" "Auth database"
verify_clean "$SCRIPT_DIR/auth-server/keys/" "JWT keys"
verify_clean "$SCRIPT_DIR/logs/" "Log files"
verify_clean "$SCRIPT_DIR/demo_pids.txt" "PID file"

echo ""
echo -e "${GREEN}🎉 Token Exchange V2 demo cleanup completed successfully!${NC}"
echo ""
echo -e "${BLUE}📋 What was cleaned:${NC}"
echo "   ✅ Keycloak realm and Token Exchange V2 configuration"
echo "   ✅ All databases (users, permissions, sessions)"
echo "   ✅ JWT keys (will be auto-generated on next start)"
echo "   ✅ Log files and session data"
echo "   ✅ Python cache and bytecode"
echo "   ✅ Browser cookies for localhost"
echo "   ✅ Background processes"
echo ""
echo -e "${GREEN}🚀 Ready for a fresh Token Exchange V2 demo start!${NC}"
echo "   Run: ${BLUE}$SCRIPT_DIR/start_demo.sh${NC}"
echo ""
echo -e "${YELLOW}💡 Tip: Use $SCRIPT_DIR/stop_demo.sh for normal shutdown (preserves data)${NC}"
echo -e "${YELLOW}     Use $SCRIPT_DIR/cleanup_demo.sh for complete reset (removes everything)${NC}"