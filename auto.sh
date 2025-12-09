
#!/bin/bash

#######################################################
# Pterodactyl Auto-Stop Script with Telegram Notification
# Script untuk auto-stop server yang running > 24 jam
#######################################################

# ========== KONFIGURASI - EDIT INI ==========
PANEL_URL="https://panelsaluler.jhonaley.net"  # URL Panel Pterodactyl Anda
API_KEY="ptla_dTyvAmxpZLLBb2h4egKi76YcT7GAlpKRPubfGUkhiHq"      # API Key dari panel (Admin -> Application API)
MAX_UPTIME=86400                       # Waktu maksimal dalam detik (86400 = 24 jam)
LOG_FILE="/var/log/pterodactyl-autostop.log"
EXCLUDED_SERVERS=""                    # Server ID yang dikecualikan, pisahkan dengan koma: "1,2,3"

# Konfigurasi Telegram
TELEGRAM_BOT_TOKEN="8216553034:AAHKxGfSMbV2oW-kj98J3z1Q-RUhSngOgpU"
TELEGRAM_CHAT_ID="@nanodesuhuhu"
TELEGRAM_ENABLED=true                  # Set false untuk disable notifikasi Telegram
# ============================================

# Warna untuk output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Fungsi logging
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Fungsi kirim notifikasi Telegram
send_telegram() {
    local message="$1"
    
    if [ "$TELEGRAM_ENABLED" = true ] && [ -n "$TELEGRAM_BOT_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ]; then
        # Escape karakter khusus untuk Telegram MarkdownV2
        message=$(echo "$message" | sed 's/[_*\[\]()~`>#+=|{}.!-]/\\&/g')
        
        curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
             -d "chat_id=${TELEGRAM_CHAT_ID}" \
             -d "text=${message}" \
             -d "parse_mode=MarkdownV2" &>/dev/null
        
        if [ $? -eq 0 ]; then
            log "📱 Telegram notification sent"
        else
            log "❌ Failed to send Telegram notification"
        fi
    fi
}

# Fungsi kirim notifikasi Telegram HTML format (lebih mudah)
send_telegram_html() {
    local message="$1"
    
    if [ "$TELEGRAM_ENABLED" = true ] && [ -n "$TELEGRAM_BOT_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ]; then
        curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
             -d "chat_id=${TELEGRAM_CHAT_ID}" \
             -d "text=${message}" \
             -d "parse_mode=HTML" &>/dev/null
        
        if [ $? -eq 0 ]; then
            log "📱 Telegram notification sent"
        else
            log "❌ Failed to send Telegram notification"
        fi
    fi
}

# Test koneksi Telegram di awal
test_telegram() {
    if [ "$TELEGRAM_ENABLED" = true ]; then
        local test_msg="🔄 Pterodactyl Auto-Stop Script Started"
        send_telegram_html "$test_msg"
    fi
}

# Validasi konfigurasi
if [ "$PANEL_URL" == "https://panel.domain.com" ] || [ "$API_KEY" == "ptla_YOUR_API_KEY_HERE" ]; then
    echo -e "${RED}ERROR: Silakan edit PANEL_URL dan API_KEY di script ini terlebih dahulu!${NC}"
    exit 1
fi

log "========== Script Auto-Stop Dimulai =========="
log "Max Uptime: $MAX_UPTIME detik ($(($MAX_UPTIME / 3600)) jam)"

# Test koneksi Telegram
test_telegram

# Get semua server dari API
RESPONSE=$(curl -s -H "Authorization: Bearer $API_KEY" \
                   -H "Accept: application/json" \
                   "$PANEL_URL/api/application/servers")

# Cek jika API call gagal
if [ $? -ne 0 ]; then
    log "ERROR: Gagal koneksi ke Pterodactyl API"
    send_telegram_html "❌ <b>ERROR</b>: Gagal koneksi ke Pterodactyl API"
    exit 1
fi

# Parse server data
SERVERS=$(echo "$RESPONSE" | jq -r '.data[]')

if [ -z "$SERVERS" ]; then
    log "WARNING: Tidak ada server ditemukan atau format response salah"
    exit 0
fi

STOPPED_COUNT=0
TOTAL_CHECKED=0
STOPPED_SERVERS=""

# Loop semua server
echo "$RESPONSE" | jq -c '.data[]' | while read -r server; do
    SERVER_ID=$(echo "$server" | jq -r '.attributes.id')
    SERVER_NAME=$(echo "$server" | jq -r '.attributes.name')
    SERVER_UUID=$(echo "$server" | jq -r '.attributes.uuid')
    SERVER_IDENTIFIER=$(echo "$server" | jq -r '.attributes.identifier')
    
    # Skip jika server ada di excluded list
    if [[ ",$EXCLUDED_SERVERS," == *",$SERVER_ID,"* ]]; then
        log "⏭️  Skipping excluded server: $SERVER_NAME (ID: $SERVER_ID)"
        continue
    fi
    
    TOTAL_CHECKED=$((TOTAL_CHECKED + 1))
    
    # Get detail resource usage untuk cek uptime dan status
    RESOURCES=$(curl -s -H "Authorization: Bearer $API_KEY" \
                        -H "Accept: application/json" \
                        "$PANEL_URL/api/client/servers/$SERVER_IDENTIFIER/resources")
    
    CURRENT_STATE=$(echo "$RESOURCES" | jq -r '.attributes.current_state')
    UPTIME=$(echo "$RESOURCES" | jq -r '.attributes.resources.uptime // 0')
    
    # Convert uptime ke jam untuk display
    UPTIME_HOURS=$(echo "scale=2; $UPTIME / 3600" | bc 2>/dev/null || echo "0")
    
    log "🔍 Checking: $SERVER_NAME (ID: $SERVER_ID) - Status: $CURRENT_STATE - Uptime: ${UPTIME_HOURS}h"
    
    # Cek jika server running dan uptime > MAX_UPTIME
    if [ "$CURRENT_STATE" == "running" ] && [ "$UPTIME" -gt "$MAX_UPTIME" ]; then
        log "⚠️  Server $SERVER_NAME telah running selama ${UPTIME_HOURS} jam (>${MAX_UPTIME}s)"
        
        # Kirim command stop
        STOP_RESPONSE=$(curl -s -X POST \
                             -H "Authorization: Bearer $API_KEY" \
                             -H "Accept: application/json" \
                             -H "Content-Type: application/json" \
                             "$PANEL_URL/api/client/servers/$SERVER_IDENTIFIER/power" \
                             -d '{"signal":"stop"}')
        
        if [ $? -eq 0 ]; then
            log "✅ Successfully stopped: $SERVER_NAME"
            STOPPED_COUNT=$((STOPPED_COUNT + 1))
            
            # Kirim notifikasi Telegram untuk setiap server yang di-stop
            TELEGRAM_MSG="⚠️ <b>Server Auto-Stopped</b>

🖥 <b>Server:</b> $SERVER_NAME
🆔 <b>ID:</b> $SERVER_ID
⏱ <b>Uptime:</b> ${UPTIME_HOURS} jam
⏰ <b>Waktu:</b> $(date '+%Y-%m-%d %H:%M:%S')
📊 <b>Status:</b> Stopped

Server telah dimatikan otomatis karena running lebih dari $(($MAX_UPTIME / 3600)) jam."
            
            send_telegram_html "$TELEGRAM_MSG"
            
            # Simpan info server yang di-stop untuk summary
            STOPPED_SERVERS="${STOPPED_SERVERS}• $SERVER_NAME (${UPTIME_HOURS}h)\n"
        else
            log "❌ Failed to stop: $SERVER_NAME"
            
            # Kirim notifikasi error ke Telegram
            ERROR_MSG="❌ <b>Failed to Stop Server</b>

🖥 <b>Server:</b> $SERVER_NAME
🆔 <b>ID:</b> $SERVER_ID
⏰ <b>Waktu:</b> $(date '+%Y-%m-%d %H:%M:%S')

Gagal menghentikan server. Silakan cek manual."
            
            send_telegram_html "$ERROR_MSG"
        fi
        
        # Delay untuk menghindari rate limit API
        sleep 2
    fi
done

log "========== Script Selesai =========="
log "Total server checked: $TOTAL_CHECKED"
log "Total server stopped: $STOPPED_COUNT"

# Kirim summary notifikasi ke Telegram jika ada server yang di-stop
if [ $STOPPED_COUNT -gt 0 ]; then
    SUMMARY_MSG="📊 <b>Auto-Stop Summary</b>

✅ <b>Total Stopped:</b> $STOPPED_COUNT server
🔍 <b>Total Checked:</b> $TOTAL_CHECKED server
⏰ <b>Waktu:</b> $(date '+%Y-%m-%d %H:%M:%S')

<b>Server yang dimatikan:</b>
$STOPPED_SERVERS
────────────────────
Semua server telah dimatikan otomatis."
    
    send_telegram_html "$SUMMARY_MSG"
else
    # Kirim notifikasi bahwa tidak ada server yang perlu di-stop
    NO_ACTION_MSG="✅ <b>Auto-Stop Check Complete</b>

🔍 <b>Total Checked:</b> $TOTAL_CHECKED server
📊 <b>Status:</b> Tidak ada server yang perlu dimatikan
⏰ <b>Waktu:</b> $(date '+%Y-%m-%d %H:%M:%S')

Semua server running normal atau uptime masih di bawah $(($MAX_UPTIME / 3600)) jam."
    
    send_telegram_html "$NO_ACTION_MSG"
fi

log ""
