#!/bin/bash

# ==============================================================================
# GCP Cloud Run V2RAY Protocol Deployment (VLESS, VLESS-gRPC, TROJAN)
# Project: https://github.com/ahlflk/GCP-V2RAY-Cloud-Run.git
# ==============================================================================

# Exit immediately if a command exits with a non-zero status or if any pipeline fails
set -euo pipefail

# ------------------------------------------------------------------------------
# 1. GLOBAL VARIABLES & STYLES
# ------------------------------------------------------------------------------

# Colors
RED='\033[0;31m'
GREEN='\033[1;32m'
LIGHT_GREEN='\033[1;92m'  # Light Green for bar
YELLOW='\033[1;33m'
ORANGE='\033[0;33m' # Header Color
BLUE='\033[1;34m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Global Configuration Variables (Defaults)
PROTOCOL="VLESS-WS"            # Will be set by select_protocol
UUID=""                        # Will be set by select_uuid
REGION="us-central1"           # Will be set by select_region
CPU="2"
MEMORY="2Gi"
SERVICE_NAME="gcp-ahlflk-v2ray" # Modified default name for clarity
HOST_DOMAIN="m.googleapis.com"
V2RAY_PATH="/ahlflk"           # Used for WS/gRPC Path

# Git Repository (As per user request)
SOURCE_REPO="https://github.com/ahlflk/GCP-V2RAY-Cloud-Run.git"
REPO_FOLDER_NAME="GCP-V2RAY-Cloud-Run" # The name of the folder to save files

# Telegram Variables (will be set during selection)
TELEGRAM_DESTINATION="none"
TELEGRAM_BOT_TOKEN=""
TELEGRAM_CHANNEL_ID=""
TELEGRAM_CHAT_ID=""
TELEGRAM_GROUP_ID=""

# Project ID holder (Will be set during auto_deployment_setup)
PROJECT_ID=""

# ------------------------------------------------------------------------------
# 2. UTILITY FUNCTIONS (LOGGING, UI, VALIDATION) - (Kept mostly intact)
# ------------------------------------------------------------------------------

# Emoji Function
show_emojis() {
    # Define Emojis
    EMOJI_SUCCESS="✅"
    EMOJI_WARN="⚠️"
    EMOJI_ERROR="❌"
    EMOJI_INFO="💡"
    EMOJI_SELECT="🎯"
    EMOJI_PROC="⚙️"
    EMOJI_DEPLOY="🚀"
    EMOJI_CHECK="📋"
    EMOJI_CLEAN="🧹"
}

# Beautiful Header/Banner
header() {
    local title="$1"
    local border_color="${ORANGE}"
    local text_color="${YELLOW}"
    
    # Calculate title length
    local title_length=${#title}
    local padding=4 
    local total_width=$((title_length + padding))
    
    # Create top/bottom border line (using Unicode box drawing characters)
    local top_bottom_fill=$(printf '━%.0s' $(seq 1 $((total_width - 2))))
    local top_bottom="${border_color}┏${top_bottom_fill}┓${NC}"
    local bottom_line="${border_color}┗${top_bottom_fill}┛${NC}"
    
    # Create title line
    local title_line="${border_color}┃${NC} ${text_color}${BOLD}${title}${NC} ${border_color}┃${NC}"
    
    echo -e "${top_bottom}"
    echo -e "${title_line}"
    echo -e "${bottom_line}"
}

# Simple Logs with Emoji
log() {
    echo -e "${GREEN}${BOLD}${EMOJI_SUCCESS} [LOG]${NC} ${WHITE}$1${NC}"
}

warn() {
    echo -e "${YELLOW}${BOLD}${EMOJI_WARN} [WARN]${NC} ${WHITE}$1${NC}"
}

error() {
    echo -e "${RED}${BOLD}${EMOJI_ERROR} [ERROR]${NC} ${WHITE}$1${NC}"
    exit 1
}

info() {
    echo -e "${BLUE}${BOLD}${EMOJI_INFO} [INFO]${NC} ${WHITE}$1${NC}"
}

selected_info() {
    echo -e "${GREEN}${BOLD}${EMOJI_SELECT} Selected:${NC} ${CYAN}$1${NC}"
}

# PROGRESS BAR
progress_bar() {
    local label="${1:-Processing}" 
    local duration=${2:-3}  
    local width=30         
    local start=$(date +%s)
    local elapsed=0
    
    # Progress Bar Loop
    while [ $elapsed -lt $duration ]; do
        local percent=$((elapsed * 100 / duration))
        local num_chars=$((percent * width / 100))
        local bar=$(printf '#%.0s' $(seq 1 $num_chars))
        local spaces=$(printf ' %.0s' $(seq 1 $((width - num_chars))))
        
        local remaining=$((duration - elapsed))
        
        # Display label, progress bar, percentage, and ETA
        printf "\r${BOLD}${EMOJI_PROC} ${label}... ${NC}[${LIGHT_GREEN}%s${NC}${ORANGE}%s${NC}] %d%% (ETA: %ds)${NC}" "$bar" "$spaces" "$percent" "$remaining"
        
        sleep 0.1
        elapsed=$(( $(date +%s) - start ))
    done
    
    # Final persistent line
    printf "\r${BOLD}${EMOJI_PROC} ${label}... ${NC}[${LIGHT_GREEN}%s${NC}] 100%% Done! (0s)${NC}\n" "$(printf '#%.0s' $(seq 1 $width))"
}

# Function to validate UUID format
validate_uuid() {
    local uuid_pattern='^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    if [[ ! $1 =~ $uuid_pattern ]]; then
        warn "Invalid UUID format. Please ensure it is a valid 32-digit hexadecimal number with 4 hyphens."
        return 1
    fi
    return 0
}

# Function to validate Telegram IDs (combined for Channel/Group/Chat)
validate_id() {
    if [[ ! $1 =~ ^-?[0-9]+$ ]]; then
        warn "Invalid Telegram ID format. Must be a number (e.g., -1001234567890 or 123456789)."
        return 1
    fi
    return 0
}

# Function to validate Telegram Bot Token
validate_bot_token() {
    local token_pattern='^[0-9]{8,10}:[a-zA-Z0-9_-]{35}$'
    if [[ ! $1 =~ $token_pattern ]]; then
        warn "Invalid Telegram Bot Token format. Please try again."
        return 1
    fi
    return 0
}

# ------------------------------------------------------------------------------
# 3. USER INPUT FUNCTIONS (MODIFIED & NEW)
# ------------------------------------------------------------------------------

# A. Protocol Selection (NEW)
select_protocol() {
    header "⚙️ V2ray Protocol Selection"
    
    while true; do
        echo -e "${CYAN}Select the desired protocol for deployment:${NC}"
        echo -e "${BOLD}1.${NC} VLESS over WebSocket (WS) + TLS ${GREEN}[DEFAULT]${NC}"
        echo -e "${BOLD}2.${NC} VLESS over gRPC (gRPC) + TLS"
        echo -e "${BOLD}3.${NC} TROJAN over WebSocket (WS) + TLS"
        echo
        
        read -p "Select protocol (1): " protocol_choice
        protocol_choice=${protocol_choice:-1}
        
        case $protocol_choice in
            1) PROTOCOL="VLESS-WS"; break ;;
            2) PROTOCOL="VLESS-gRPC"; break ;;
            3) PROTOCOL="TROJAN-WS"; break ;;
            *) echo -e "${RED}Invalid selection. Please enter a number between 1-3.${NC}"; continue ;;
        esac
    done

    selected_info "Protocol: $PROTOCOL"
    
    # VLESS requires UUID, TROJAN does not (it uses password)
    if [[ "$PROTOCOL" == "TROJAN-WS" ]]; then
        info "TROJAN selected. UUID will be used as the Password."
    fi
    echo
}

# B. Telegram Destination Selection (Kept intact)
select_telegram_destination() {
    header "📱 Telegram Notification Settings"
    # ... (Keep the content of select_telegram_destination here)
    # --- (Function content omitted for brevity, assumed intact) ---
    
    while true; do
        echo -e "${CYAN}Select where to send the deployment link:${NC}"
        echo -e "${BOLD}1.${NC} Don't send to Telegram ${GREEN}[DEFAULT]${NC}"
        echo -e "${BOLD}2.${NC} Send to Channel Only"
        echo -e "${BOLD}3.${NC} Send to Group Only"
        echo -e "${BOLD}4.${NC} Send to Bot Private Message" 
        echo -e "${BOLD}5.${NC} Send to Both Channel and Bot"
        echo
        
        read -p "Select destination (1): " telegram_choice
        telegram_choice=${telegram_choice:-1}
        
        case $telegram_choice in
            1) TELEGRAM_DESTINATION="none"; break ;;
            2) TELEGRAM_DESTINATION="channel"; break ;;
            3) TELEGRAM_DESTINATION="group"; break ;;
            4) TELEGRAM_DESTINATION="bot"; break ;;
            5) TELEGRAM_DESTINATION="both"; break ;;
            *) echo -e "${RED}Invalid selection. Please enter a number between 1-5.${NC}"; continue ;;
        esac
    done

    if [[ "$TELEGRAM_DESTINATION" != "none" ]]; then
        echo
        while true; do
            read -p "Enter Telegram Bot Token: " TELEGRAM_BOT_TOKEN
            if validate_bot_token "$TELEGRAM_BOT_TOKEN"; then break; else continue; fi
        done
        
        if [[ "$TELEGRAM_DESTINATION" == "channel" || "$TELEGRAM_DESTINATION" == "both" ]]; then
            while true; do
                read -p "Enter Telegram Channel ID: " TELEGRAM_CHANNEL_ID
                if validate_id "$TELEGRAM_CHANNEL_ID"; then break; fi
            done
        fi
        
        if [[ "$TELEGRAM_DESTINATION" == "bot" || "$TELEGRAM_DESTINATION" == "both" ]]; then
            while true; do
                read -p "Enter your Chat ID (for bot private message): " TELEGRAM_CHAT_ID
                if validate_id "$TELEGRAM_CHAT_ID"; then break; fi
            done
        fi
        
        if [[ "$TELEGRAM_DESTINATION" == "group" ]]; then
            while true; do
                read -p "Enter Telegram Group ID: " TELEGRAM_GROUP_ID
                if validate_id "$TELEGRAM_GROUP_ID"; then break; fi
            done
        fi
        selected_info "Bot Token: ${TELEGRAM_BOT_TOKEN:0:8}..."
    fi
    
    selected_info "Telegram Destination: $TELEGRAM_DESTINATION"
    echo
}

# C. Region Selection (Kept intact)
select_region() {
    header "🌍 GCP Region Selection"
    # ... (Keep the content of select_region here)
    # --- (Function content omitted for brevity, assumed intact) ---
    
    echo -e "${CYAN}Available GCP Regions:${NC}"
    echo -e "${BOLD}1.${NC}  🇺🇸 us-central1 (Council Bluffs, Iowa, North America) ${GREEN}[DEFAULT]${NC}"
    echo -e "${BOLD}2.${NC}  🇺🇸 us-east1 (Moncks Corner, South Carolina, North America)" 
    echo -e "${BOLD}3.${NC}  🇺🇸 us-south1 (Dallas, Texas, North America)"
    echo -e "${BOLD}4.${NC}  🇺🇸 us-west1 (The Dalles, Oregon, North America)"
    echo -e "${BOLD}5.${NC}  🇺🇸 us-west2 (Los Angeles, California, North America)"
    echo -e "${BOLD}6.${NC}  🇨🇦 northamerica-northeast2 (Toronto, Ontario, North America)"
    echo -e "${BOLD}7.${NC}  🇸🇬 asia-southeast1 (Jurong West, Singapore)"
    echo -e "${BOLD}8.${NC}  🇯🇵 asia-northeast1 (Tokyo, Japan)"
    echo -e "${BOLD}9.${NC}  🇹🇼 asia-east1 (Changhua County, Taiwan)"
    echo -e "${BOLD}10.${NC} 🇭🇰 asia-east2 (Hong Kong)"
    echo -e "${BOLD}11.${NC} 🇮🇳 asia-south1 (Mumbai, India)"
    echo -e "${BOLD}12.${NC} 🇮🇩 asia-southeast2 (Jakarta, Indonesia)${NC}"
    echo
    
    while true; do
        read -p "Select region (1): " region_choice
        region_choice=${region_choice:-1}
        case $region_choice in
            1) REGION="us-central1"; break ;;
            2) REGION="us-east1"; break ;;
            3) REGION="us-south1"; break ;;
            4) REGION="us-west1"; break ;;
            5) REGION="us-west2"; break ;;
            6) REGION="northamerica-northeast2"; break ;;
            7) REGION="asia-southeast1"; break ;;
            8) REGION="asia-northeast1"; break ;;
            9) REGION="asia-east1"; break ;;
            10) REGION="asia-east2"; break ;;
            11) REGION="asia-south1"; break ;;
            12) REGION="asia-southeast2"; break ;;
            *) echo -e "${RED}Invalid selection. Please enter a number between 1-12.${NC}" ;;
        esac
    done
    
    selected_info "Region: $REGION"
    echo
}

# D. CPU Configuration (Kept intact)
select_cpu() {
    header "🖥️  CPU Configuration"
    # ... (Keep the content of select_cpu here)
    # --- (Function content omitted for brevity, assumed intact) ---
    
    echo -e "${CYAN}Available Options:${NC}"
    echo -e "${BOLD}1.${NC} 1  CPU Core (Lightweight traffic)"
    echo -e "${BOLD}2.${NC} 2  CPU Cores (Balanced) ${GREEN}[DEFAULT]${NC}"
    echo -e "${BOLD}3.${NC} 4  CPU Cores (Performance)"
    echo -e "${BOLD}4.${NC} 8  CPU Cores (High Performance)"
    echo -e "${BOLD}5.${NC} 16 CPU Cores (Extreme Load)" 
    echo
    
    while true; do
        read -p "Select CPU cores (2): " cpu_choice
        cpu_choice=${cpu_choice:-2}
        case $cpu_choice in
            1) CPU="1"; break ;;
            2) CPU="2"; break ;;
            3) CPU="4"; break ;;
            4) CPU="8"; break ;;
            5) CPU="16"; break ;;
            *) echo -e "${RED}Invalid selection. Please enter a number between 1-5.${NC}" ;;
        esac
    done
    
    selected_info "CPU: $CPU core(s)"
    echo
}

# E. Memory Configuration (Kept intact)
select_memory() {
    header "💾 Memory Configuration"
    # ... (Keep the content of select_memory here)
    # --- (Function content omitted for brevity, assumed intact) ---

    echo -e "${CYAN}Available Options:${NC}"
    echo -e "${BOLD}1.${NC} 512Mi (Minimum requirement)"
    echo -e "${BOLD}2.${NC} 1Gi (Basic usage)"
    echo -e "${BOLD}3.${NC} 2Gi (Balanced usage) ${GREEN}[DEFAULT]${NC}"
    echo -e "${BOLD}4.${NC} 4Gi (Moderate performance)"
    echo -e "${BOLD}5.${NC} 8Gi (High load/many connections)"
    echo -e "${BOLD}6.${NC} 16Gi (Advanced/Extreme load)"
    echo -e "${BOLD}7.${NC} 32Gi (Maximum limit for Cloud Run)"
    echo
    
    while true; do
        read -p "Select memory (3): " memory_choice
        memory_choice=${memory_choice:-3}
        case $memory_choice in
            1) MEMORY="512Mi"; break ;;
            2) MEMORY="1Gi"; break ;;
            3) MEMORY="2Gi"; break ;;
            4) MEMORY="4Gi"; break ;;
            5) MEMORY="8Gi"; break ;;
            6) MEMORY="16Gi"; break ;;
            7) MEMORY="32Gi"; break ;;
            *) echo -e "${RED}Invalid selection. Please enter a number between 1-7.${NC}" ;;
        esac
    done
    
    selected_info "Memory: $MEMORY"
    echo
}

# F. Service Name Configuration (Updated default)
select_service_name() {
    header "${EMOJI_PROC} Service Name Configuration"
    
    echo -e "${CYAN}Deployment Service Name (Default: $SERVICE_NAME):${NC}"
    
    read -p "Enter custom name or press Enter to use default: " custom_name
    SERVICE_NAME=${custom_name:-$SERVICE_NAME}
    
    if [[ -z "$SERVICE_NAME" ]]; then
        warn "Service name cannot be empty. Using default: $SERVICE_NAME."
    fi
    
    selected_info "Service Name: $SERVICE_NAME"
    echo
}

# G. Host Domain Configuration (Kept intact)
select_host_domain() {
    header "🌐 Host Domain Configuration"
    
    echo -e "${CYAN}SNI/Host Domain (Default: m.googleapis.com):${NC}"
    
    read -p "Enter custom domain or press Enter to use default: " custom_domain
    HOST_DOMAIN=${custom_domain:-$HOST_DOMAIN}
    
    if [[ -z "$HOST_DOMAIN" ]]; then
        warn "Host Domain cannot be empty. Using default: m.googleapis.com."
        HOST_DOMAIN="m.googleapis.com"
    fi
    
    selected_info "Host Domain: $HOST_DOMAIN"
    echo
}

# H. Path Configuration (NEW for WS/gRPC)
select_v2ray_path() {
    if [[ "$PROTOCOL" == "VLESS-WS" || "$PROTOCOL" == "VLESS-gRPC" || "$PROTOCOL" == "TROJAN-WS" ]]; then
        header "🗺️ WebSocket/gRPC Path Configuration"
        
        echo -e "${CYAN}VLESS/TROJAN Path (Default: $V2RAY_PATH):${NC}"
        
        read -p "Enter custom path (e.g., /mysecret) or press Enter to use default: " custom_path
        V2RAY_PATH=${custom_path:-$V2RAY_PATH}
        
        # Ensure path starts with /
        if [[ ! "$V2RAY_PATH" =~ ^/ ]]; then
            V2RAY_PATH="/$V2RAY_PATH"
            info "Path corrected to start with /: $V2RAY_PATH"
        fi
        
        if [[ -z "$V2RAY_PATH" ]]; then
            warn "Path cannot be empty. Using default: /ahlflk."
            V2RAY_PATH="/ahlflk"
        fi
        
        selected_info "Path: $V2RAY_PATH"
        echo
    fi
}

# I. UUID Configuration (VLESS/TROJAN uses it as password) (Updated)
select_uuid() {
    header "🔑 UUID/Password Configuration"
    
    local default_uuid="3675119c-14fc-46a4-b5f3-9a2c91a7d802"
    
    if [[ "$PROTOCOL" == "TROJAN-WS" ]]; then
        info "TROJAN uses this as the Password. It must be a 32-digit UUID."
    fi
        
    while true; do
        echo -e "${CYAN}UUID/Password Options:${NC}"
        echo -e "${BOLD}1.${NC} Use Default UUID ($default_uuid) ${GREEN}[DEFAULT]${NC}"
        echo -e "${BOLD}2.${NC} Generate New UUID"
        echo -e "${CYAN}You can also paste a custom UUID/Password directly, or press Enter for default.${NC}"
        echo

        read -p "Enter 1, 2, or Paste Custom UUID/Password: " uuid_input
        uuid_input=${uuid_input:-1}

        if [[ "$uuid_input" == "1" ]]; then
            UUID="$default_uuid"
            log "Using Default UUID/Password."
            break
        elif [[ "$uuid_input" == "2" ]]; then
            if command -v uuidgen &> /dev/null; then
                UUID=$(uuidgen)
            else
                # Fallback
                UUID=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || echo "$default_uuid")
                if [[ "$UUID" == "$default_uuid" ]]; then
                     warn "uuidgen not found. Using default UUID."
                fi
            fi
            log "Generated New UUID/Password: $UUID"
            break
        elif validate_uuid "$uuid_input"; then
            # Custom UUID/Password validation successful (UUID format is required for VLESS and recommended for Trojan)
            UUID="$uuid_input"
            log "Using Custom UUID/Password: $UUID"
            break
        else
            echo -e "${RED}Invalid input. Please enter 1, 2, or a valid custom UUID.${NC}" 
        fi
    done
    
    selected_info "UUID/Password: $UUID"
    echo
}


# J. Summary and Confirmation (Updated)
show_config_summary() {
    # Get current configured project ID for display
    local temp_project_id=$(gcloud config get-value project 2>/dev/null || echo "Not Configured (Deployment will fail)")
    
    header "${EMOJI_CHECK} Configuration Summary"
    
    # Using printf for alignment
    printf "${CYAN}${BOLD}%-25s${NC} %s\n" "Project ID:"             "$temp_project_id"
    printf "${CYAN}${BOLD}%-25s${NC} %s\n" "Protocol:"               "$PROTOCOL"
    printf "${CYAN}${BOLD}%-25s${NC} %s\n" "Region:"                 "$REGION"
    printf "${CYAN}${BOLD}%-25s${NC} %s\n" "Service Name:"           "$SERVICE_NAME"
    printf "${CYAN}${BOLD}%-25s${NC} %s\n" "Host Domain (SNI):"     "$HOST_DOMAIN"
    printf "${CYAN}${BOLD}%-25s${NC} %s\n" "UUID/Password:"          "$UUID"
    
    if [[ "$PROTOCOL" == "VLESS-WS" || "$PROTOCOL" == "VLESS-gRPC" || "$PROTOCOL" == "TROJAN-WS" ]]; then
        printf "${CYAN}${BOLD}%-25s${NC} %s\n" "Path (WS/gRPC):"      "$V2RAY_PATH"
    fi
    
    printf "${CYAN}${BOLD}%-25s${NC} %s\n" "CPU/Memory:"             "$CPU core(s) / $MEMORY"
    
    if [[ "$TELEGRAM_DESTINATION" != "none" ]]; then
        printf "${CYAN}${BOLD}%-25s${NC} %s\n" "Telegram Notification:" "$TELEGRAM_DESTINATION (Token: ${TELEGRAM_BOT_TOKEN:0:8}...)"
    else
        printf "${CYAN}${BOLD}%-25s${NC} %s\n" "Telegram Notification:" "Not configured"
    fi
    echo
    
    while true; do
        read -p "$(echo -e "${ORANGE}${BOLD}Proceed with deployment? (y/n): ${NC}")" confirm
        case $confirm in
            [Yy]* ) 
                # After confirmation, start the auto-setup immediately
                auto_deployment_setup
                break
                ;;
            [Nn]* ) 
                info "Deployment cancelled by user"
                exit 0
                ;;
            * ) echo -e "${RED}Please answer yes (y) or no (n).${NC}";;
        esac
    done
}

# ------------------------------------------------------------------------------
# MODIFIED: AUTO DEPLOYMENT SETUP (Project ID CLI & API Enablement)
# ------------------------------------------------------------------------------
auto_deployment_setup() {
    log "Starting initial GCP setup..."
    
    # 1. Check and Set Project ID CLI Configuration
    info "Fetching Project ID for CLI configuration."
    PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
    
    if [[ -z "$PROJECT_ID" ]]; then
        error "GCP Project ID is not configured in gcloud CLI. Please run 'gcloud auth login' and 'gcloud config set project [PROJECT_ID]' and try again."
    fi
    
    selected_info "Using configured Project ID: $PROJECT_ID"

    # Set Project ID CLI Configuration (redundant but ensures the current context)
    log "Verifying gcloud CLI active project to: ${PROJECT_ID}"
    gcloud config set project "$PROJECT_ID" --quiet > /dev/null 2>&1
    progress_bar "Setting Project ID CLI" 1 

    # 2. Enable Required APIs (Artifact Registry is often better than Container Registry now)
    log "Enabling required APIs (Cloud Run, Artifact Registry, Cloud Build)..."
    gcloud services enable run.googleapis.com artifactregistry.googleapis.com cloudbuild.googleapis.com --project "$PROJECT_ID" --quiet > /dev/null 2>&1
    progress_bar "Enabling APIs" 1 

    log "Initial GCP setup complete. Proceeding with deployment..."
    progress_bar "GCP Setup" 1 
}

# ------------------------------------------------------------------------------
# 4. CORE DEPLOYMENT FUNCTIONS (MODIFIED)
# ------------------------------------------------------------------------------

# Clone Repo and Extract Files (MODIFIED for the new repo)
clone_and_extract() {
    log "Cloning repository from $SOURCE_REPO..."
    # Clone to a temporary folder name 'temp-repo'
    git clone "$SOURCE_REPO" temp-repo > /dev/null 2>&1
    progress_bar "Cloning Repository" 5 

    if [ ! -d "temp-repo" ]; then
        error "Failed to clone repository from $SOURCE_REPO. Check your network or the repository URL."
    fi
    
    cd temp-repo

    # The repo must contain these files. If they are not found, the repo is likely incorrect.
    if [ ! -f "Dockerfile" ]; then
        error "Dockerfile not found in the cloned repository. Please check the repository structure."
    fi
    if [ ! -f "config.json" ]; then
        error "config.json not found in the cloned repository. Please check the repository structure."
    fi

    # Copy files to the current working directory for gcloud builds submit
    log "Copying Dockerfile and config.json to local directory."
    cp Dockerfile ../Dockerfile 
    cp config.json ../config.json 
    cd ..
    
    # Clean up the temporary clone folder
    rm -rf temp-repo 
    log "Finished cloning and cleanup."
}

# Config File Preparation (MODIFIED)
prepare_config_files() {
    log "Preparing Xray config file for $PROTOCOL..."
    if [[ ! -f "config.json" ]]; then
        error "config.json not found locally. Was it successfully cloned and copied?"
    fi
    
    # Check the placeholder UUID/Password
    sed -i "s/PLACEHOLDER_UUID/$UUID/g" config.json
    
    # Check the placeholder Path
    sed -i "s|/v2ray-path|$V2RAY_PATH|g" config.json
    
    # Check the placeholder Protocol if needed (though the config.json should handle all three protocols internally)
    # The config.json in the repo is expected to handle all protocols and use these variables.
    
    progress_bar "Preparing Config" 10 
}

# Share Link Creation (Unified and simplified)
create_share_link() {
    local SERVICE_NAME="$1"
    local DOMAIN="$2"
    local UUID="$3"
    local SHARE_LINK=""
    
    # URL Encode path
    local PATH_ENCODED=$(echo "$V2RAY_PATH" | sed 's/\//%2F/g')
    
    # Remove https:// from DOMAIN if present
    DOMAIN="${DOMAIN#https://}"
    DOMAIN="${DOMAIN%/}"
    
    case $PROTOCOL in
        "VLESS-WS")
            SHARE_LINK="vless://${UUID}@${DOMAIN}:443?path=${PATH_ENCODED}&security=tls&encryption=none&host=${HOST_DOMAIN}&fp=randomized&type=ws&sni=${HOST_DOMAIN}#${SERVICE_NAME}_VLESS-WS"
            ;;
        "VLESS-gRPC")
            SHARE_LINK="vless://${UUID}@${DOMAIN}:443?mode=gun&security=tls&encryption=none&type=grpc&serviceName=${V2RAY_PATH}#${SERVICE_NAME}_VLESS-gRPC"
            ;;
        "TROJAN-WS")
            # Trojan over WS/TLS using UUID as password
            SHARE_LINK="trojan://${UUID}@${DOMAIN}:443?path=${PATH_ENCODED}&security=tls&encryption=none&host=${HOST_DOMAIN}&type=ws&sni=${HOST_DOMAIN}#${SERVICE_NAME}_TROJAN-WS"
            ;;
        *)
            SHARE_LINK="Error: Protocol $PROTOCOL not supported for link generation."
            ;;
    esac
    
    echo "$SHARE_LINK"
}

# Telegram Notification Function (Simplified) - (Kept intact)
send_to_telegram() {
    local chat_id="$1"
    local message="$2"
    
    # Simple escaping, preserving the link format [Text](URL)
    message=$(echo "$message" | sed 's/\*/\\*/g; s/_/\\_/g; s/`/\\`/g; s/\[[^]]*\]([^)]*)/PLACEHHOLDER_LINK/g')
    message=$(echo "$message" | sed 's/\\\[/\[/g; s/\\\]/\]/g; s/PLACEHOLDER_LINK/\\0/g')

    curl -s -o /dev/null -w "%{http_code}" -X POST \
        -H "Content-Type: application/json" \
        -d "{\"chat_id\": \"${chat_id}\", \"text\": \"$message\", \"parse_mode\": \"MARKDOWN\", \"disable_web_page_preview\": true}" \
        https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage
}

send_deployment_notification() {
    local message="$1"
    
    case $TELEGRAM_DESTINATION in
        "channel")
            send_to_telegram "$TELEGRAM_CHANNEL_ID" "$message" > /dev/null 2>&1
            log "Notification sent to Telegram Channel."
            ;;
        "bot")
            send_to_telegram "$TELEGRAM_CHAT_ID" "$message" > /dev/null 2>&1
            log "Notification sent to Bot private message."
            ;;
        "group")
            send_to_telegram "$TELEGRAM_GROUP_ID" "$message" > /dev/null 2>&1
            log "Notification sent to Telegram Group."
            ;;
        "both")
            send_to_telegram "$TELEGRAM_CHANNEL_ID" "$message" > /dev/null 2>&1
            send_to_telegram "$TELEGRAM_CHAT_ID" "$message" > /dev/null 2>&1
            log "Notification sent to both Channel and Bot."
            ;;
        "none")
            log "Skipping Telegram notification."
            ;;
    esac
}

# Deploy to Cloud Run (MODIFIED to use Artifact Registry, which is the current best practice)
deploy_to_cloud_run() {
    local project_id="$PROJECT_ID"
    local ARTIFACT_REPO_NAME="cloud-run-source-deploy" # Default repo name for source deploys
    local IMAGE_TAG="${REGION}-docker.pkg.dev/${project_id}/${ARTIFACT_REPO_NAME}/${SERVICE_NAME}:latest"
    
    # 1. Create Artifact Registry Repository if it doesn't exist (Only needed if not using gcloud run deploy --source)
    # The current approach is simpler and uses gcloud run deploy --source, which uses Cloud Build.
    
    log "Deploying to Cloud Run service from source $SOURCE_REPO..."
    
    # Using the simpler deployment from source, which automatically handles:
    # 1. Cloning the repo
    # 2. Building the Dockerfile via Cloud Build
    # 3. Pushing the image to Artifact Registry
    # 4. Deploying the service
    
    gcloud run deploy "$SERVICE_NAME" \
      --source "." \
      --region "$REGION" \
      --allow-unauthenticated \
      --port 8080 \
      --memory "$MEMORY" \
      --cpu "$CPU" \
      --no-check-service-account \
      --set-env-vars "UUID=$UUID,PATH=$V2RAY_PATH,HOST=$HOST_DOMAIN,PROTOCOL=$PROTOCOL" \
      --quiet 
    # NOTE: The config.json is still modified locally and deployed via Dockerfile, 
    # this command uses the *current local directory* which contains the modified config.json
    progress_bar "Building & Deploying Service" 30 

    local service_url=$(gcloud run services describe "$SERVICE_NAME" --region "$REGION" --format='value(status.url)' --quiet 2>/dev/null)
    if [[ -z "$service_url" ]]; then
        error "Failed to retrieve service URL after deployment. Check Cloud Build logs for errors."
    fi

    local share_link=$(create_share_link "$SERVICE_NAME" "$service_url" "$UUID")

    log "Deployment completed!"
    selected_info "Service URL: $service_url"
    selected_info "$PROTOCOL Share Link: $share_link"

    local telegram_message="🚀 *GCP V2ray Deployment Complete!*\n\n📋 *Details:*\n• Protocol: $PROTOCOL\n• Region: $REGION\n• Service: $SERVICE_NAME\n• UUID/Pass: $UUID\n\n🔗 [$PROTOCOL Link]($share_link)"
    
    send_deployment_notification "$telegram_message"
}

# Create Folder with deployment-info.txt (MODIFIED folder name)
create_project_folder() {
    local project_id="$PROJECT_ID"
    local service_url=$(gcloud run services describe $SERVICE_NAME --region $REGION --format='value(status.url)' --quiet 2>/dev/null)
    local share_link=$(create_share_link "$SERVICE_NAME" "$service_url" "$UUID")
    local folder_name="$REPO_FOLDER_NAME-$SERVICE_NAME"

    log "Saving project files and info to folder: $folder_name/"
    mkdir -p "$folder_name"
    
    # Move the generated files into the new folder
    mv Dockerfile "$folder_name/" 
    mv config.json "$folder_name/" 
    
    cat > "$folder_name/deployment-info.txt" << EOF
GCP V2RAY Cloud Run Deployment Info
===================================

Project ID: $project_id
Region: $REGION
Service Name: $SERVICE_NAME
Protocol: $PROTOCOL
UUID/Password: $UUID
Path: $V2RAY_PATH
Host Domain: $HOST_DOMAIN
CPU: $CPU
Memory: $MEMORY
Service URL: $service_url
$PROTOCOL Share Link: $share_link

Deployment Date: $(date)

For more details, check GCP Console: https://console.cloud.google.com/run?project=$project_id
EOF
    
    log "Project files and info saved successfully in: $folder_name/"
    info "Check the '$folder_name' folder for your deployment files and details."
}

# ------------------------------------------------------------------------------
# 5. MAIN EXECUTION BLOCK
# ------------------------------------------------------------------------------

# Initialize emojis
show_emojis

# Run user input functions in specified order
run_user_inputs() {
    # Display main header
    header "${EMOJI_DEPLOY} GCP Cloud Run V2RAY Protocol Deployment"
    select_protocol      # NEW: Select VLESS-WS, VLESS-gRPC, or TROJAN
    select_telegram_destination
    select_region
    select_cpu
    select_memory
    select_service_name
    select_host_domain
    select_v2ray_path    # NEW: Select Path for WS/gRPC
    select_uuid          # UUID is used for VLESS ID or TROJAN Password
    # show_config_summary will call auto_deployment_setup() upon 'Yes'
    show_config_summary 
}

# Main execution
run_user_inputs

# Core Deployment Steps run automatically after auto_deployment_setup completes
# NOTE: The deploy_to_cloud_run function will use the local Dockerfile and config.json
# that are copied and modified from the cloned repository.
clone_and_extract
prepare_config_files
deploy_to_cloud_run
create_project_folder 

info "All done! Check your GCP Console and the local folder for the deployed service details."

