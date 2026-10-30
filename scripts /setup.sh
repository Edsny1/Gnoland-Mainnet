#!/usr/bin/env bash

set -euo pipefail

CHAIN_ID="gnoland-1"
GNO_BRANCH="chain/mainnet"
GENESIS_URL="https://github.com/gnolang/gno/releases/download/chain%2Fmainnet/genesis.json.gz"
GENESIS_SHA256="ea22691003130eae3ba975b7d16460706b5d75ce6c04ae82c0c4faeab7de91f0"
SNAPSHOT_URL="https://server-9.hazennetworksolutions.com/gnoland-mainnet-db-snapshot.tar.lz4"
SNAPSHOT_FALLBACK_SHA256="d0445f0d158f1d188e34f4a5b206658bc0915a151ad73a5dd38293f8242b7cf4"

RPC_REMOTE="https://rpc.gno.land"
FAUCET_URL=""
EXPLORER_URL="https://gno.land"

PERSISTENT_PEERS="g15rcv5yqef3kvnmueqvkyw8y05sd40jz9p3n5su@seed-1.gno.land:26656,g1ck2yeyvvnpl92237gcea0z68jx07a4nnyvuaan@seed-2.gno.land:26656"
VALOPERS_PKGPATH="gno.land/r/gnops/valopers"

DESCRIPTION_MAX=2048

GNO_DIR="$HOME/gno-mainnet"
DATA_DIR="$GNO_DIR/gnoland-data"
SERVICE_FILE="/etc/systemd/system/gnoland-mainnet.service"


P2P_PORT=26656
RPC_PORT=26657

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ── Helpers ───────────────────────────────────────────────────────────────────
info()    { echo -e "${CYAN}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC}   $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERR]${NC}  $*" >&2; }
die()     { error "$*"; exit 1; }

press_enter() {
    echo ""
    read -rp "  Press Enter to continue..."
}

require_cmd() {
    command -v "$1" &>/dev/null || die "'$1' not found. Run option 1 (Install Node) first."
}

gnoland_bin() {
    command -v gnoland 2>/dev/null || echo "$HOME/go/bin/gnoland"
}

# ── Banner ────────────────────────────────────────────────────────────────────
banner() {
    clear
    echo -e "${BOLD}${RED}"
    echo "  ╔═══════════════════════════════════════════════════╗"
    echo "  ║        Gnoland MAINNET — Validator Setup           ║"
    echo "  ║      Chain ID: gnoland-1  (REAL VALUE NETWORK)     ║"
    echo "  ╚═══════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# ── Main menu ─────────────────────────────────────────────────────────────────
main_menu() {
    while true; do
        banner
        echo -e "  ${BOLD}Main Menu${NC}\n"
        echo "  [1] Install node"
        echo "  [2] Check sync status"
        echo "  [3] Add wallet / Recover wallet"
        echo "  [4] Load snapshot"
        echo "  [5] Add / Update description"
        echo "  [6] Register validator candidate"
        echo "  [7] Service management"
        echo "  [8] Update node (build + wait for halt height)"
        echo "  [9] Update watcher status / logs"
        echo "  [0] Exit"
        echo ""
        read -rp "  Choose an option: " choice

        case "$choice" in
            1) install_node ;;
            2) check_sync ;;
            3) wallet_menu ;;
            4) load_snapshot ;;
            5) update_description ;;
            6) register_validator ;;
            7) service_menu ;;
            8) update_node ;;
            9) update_watcher_status ;;
            0) echo ""; exit 0 ;;
            *) warn "Invalid option, try again."; sleep 1 ;;
        esac
    done
}

# ══════════════════════════════════════════════════════════════════════════════
# 1. INSTALL NODE
# ══════════════════════════════════════════════════════════════════════════════
install_node() {
    banner
    echo -e "  ${BOLD}[1] Install Node${NC}\n"
    warn "This will fetch chain/mainnet and connect to gnoland-1, a real-value chain."
    read -rp "  Continue? [y/N]: " CONFIRM_MAINNET
    [[ "$CONFIRM_MAINNET" =~ ^[Yy]$ ]] || { info "Aborted."; press_enter; return; }

    # ── Dependencies ──────────────────────────────────────────────────────────
    info "Installing system dependencies..."
    sudo apt-get update -qq
    sudo apt-get install -y git make wget curl zstd liblz4-tool pv python3 build-essential \
        ca-certificates gnupg lsb-release 2>&1 \
        | grep -E "^(Get|Setting|Preparing|Unpacking|Processing)" || true
    success "Dependencies installed."

    # ── Docker ────────────────────────────────────────────────────────────────
    if command -v docker &>/dev/null; then
        info "Docker already installed: $(docker --version)"
    else
        info "Installing Docker..."
        sudo install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
            | sudo gpg --yes --dearmor -o /etc/apt/keyrings/docker.gpg
        sudo chmod a+r /etc/apt/keyrings/docker.gpg
        echo \
            "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
            https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
            | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
        sudo apt-get update -qq
        sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin 2>&1 \
            | grep -E "^(Get|Setting|Preparing|Unpacking|Processing)" || true
        sudo usermod -aG docker "$USER"
        sudo systemctl enable docker
        sudo systemctl start docker
        success "Docker installed: $(docker --version)"
    fi

    # ── Go ────────────────────────────────────────────────────────────────────
    _do_install_go() {
        local GO_VERSION="1.22.4"
        info "Installing Go $GO_VERSION into /usr/local/go..."
        wget -q "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz" -O /tmp/go.tar.gz
        sudo rm -rf /usr/local/go
        sudo tar -C /usr/local -xzf /tmp/go.tar.gz
        rm /tmp/go.tar.gz
        if ! grep -q '/usr/local/go/bin' ~/.bashrc; then
            echo 'export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin' >> ~/.bashrc
        fi
        export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin
        success "Go $(go version | awk '{print $3}') installed."
    }

    if command -v go &>/dev/null; then
        GO_VER_FULL=$(go version | awk '{print $3}' | tr -d 'go')
        GO_MAJOR=$(echo "$GO_VER_FULL" | cut -d. -f1)
        GO_MINOR=$(echo "$GO_VER_FULL" | cut -d. -f2)
        info "Go already installed: go$GO_VER_FULL"

        if [[ "$GO_MAJOR" -gt 1 ]] || [[ "$GO_MAJOR" -eq 1 && "$GO_MINOR" -ge 22 ]]; then
            success "Go version is sufficient (>= 1.22), skipping installation."
        else
            warn "Installed Go (go$GO_VER_FULL) is older than 1.22 — gnoland requires >= 1.22."
            warn "Upgrading will replace /usr/local/go and may affect other nodes on this server."
            read -rp "  Upgrade Go to 1.22.4? [y/N]: " UPGRADE_GO
            if [[ "$UPGRADE_GO" =~ ^[Yy]$ ]]; then
                _do_install_go
            else
                warn "Skipping Go upgrade. Build will likely fail."
            fi
        fi
    else
        _do_install_go
    fi

    # ── Clone & build ─────────────────────────────────────────────────────────
    if [[ -d "$GNO_DIR/.git" ]]; then
        info "Repo already exists at $GNO_DIR, pulling latest..."
        cd "$GNO_DIR"
        git fetch origin "$GNO_BRANCH"
        git checkout "$GNO_BRANCH"
        git pull origin "$GNO_BRANCH"
    else
        info "Cloning gno repository (branch: $GNO_BRANCH)..."
        git clone --branch "$GNO_BRANCH" --depth 1 \
            https://github.com/gnolang/gno.git "$GNO_DIR"
    fi

    info "Building gnoland and gnokey (this may take a few minutes)..."
    cd "$GNO_DIR"
    make -C gno.land install.gnoland install.gnokey
    success "Binaries built: $(which gnoland)"
    info "As of the last check, chain/mainnet's HEAD was tagged v1.5.0"
    info "(commit e75fef82c..., merged by aeddi, verified — confirmed via a"
    info "screenshot of the GitHub commit page, not independently re-fetched by"
    info "this script). chain/mainnet moves as it's re-released, so re-check the"
    info "current tag yourself rather than assuming v1.5.0 is still current:"
    info "  https://github.com/gnolang/gno/releases/tag/chain%2Fmainnet"
    warn "For a production validator, consider pinning to that tagged release"
    warn "(e.g. 'git checkout v1.5.0' or whatever the current tag is) instead of"
    warn "a floating branch head, and read RELEASING.md for the halt_min_version"
    warn "implications of running a mismatched version."

    # ── Genesis ───────────────────────────────────────────────────────────────
    if [[ -f "$GNO_DIR/genesis.json" ]]; then
        info "genesis.json already exists, verifying checksum..."
    else
        info "Downloading genesis.json.gz..."
        wget -q -O "$GNO_DIR/genesis.json.gz" "$GENESIS_URL"
        gunzip -f "$GNO_DIR/genesis.json.gz"
    fi

    ACTUAL_SHA=$(shasum -a 256 "$GNO_DIR/genesis.json" | awk '{print $1}')
    if [[ "$ACTUAL_SHA" == "$GENESIS_SHA256" ]]; then
        success "Genesis checksum matches the value pinned in this script."
        warn "That pinned value was gathered from public sources and not from a"
        warn "confirmed first-party document — cross-check it yourself against"
        warn "https://github.com/gnolang/gno/releases/tag/chain%2Fmainnet"
    else
        die "Genesis checksum mismatch!\n  Expected (from this script): $GENESIS_SHA256\n  Got:      $ACTUAL_SHA\n  DO NOT proceed — re-download from the official release page and re-verify."
    fi

    # ── Init config & secrets ─────────────────────────────────────────────────
    cd "$GNO_DIR"
    if [[ ! -f "$GNO_DIR/gnoland-data/config/config.toml" ]]; then
        info "Initializing config and secrets..."
        GNOROOT="$GNO_DIR" gnoland config init
        GNOROOT="$GNO_DIR" gnoland secrets init
        success "Config and secrets initialized."
        warn "Your validator private keys now live under $GNO_DIR/gnoland-data/secrets/."
        warn "Back these up offline immediately. Losing them or leaking them is"
        warn "irreversible on a real-value chain."
    else
        info "Config already exists, skipping init."
    fi

    # ── Node-specific config ───────────────────────────────────────────────────
    echo ""
    read -rp "  Enter your node moniker (name): " MONIKER
    read -rp "  Enter your public server IP (for p2p.external_address): " SERVER_IP
    echo ""
    echo "  Port configuration:"
    echo "  Standard gno ports: 26656 (P2P) / 26657 (RPC)"
    echo "  If another node already uses those ports, enter different values."
    echo "  Press Enter to keep the standard port."
    echo ""
    read -rp "  P2P port  [26656]: " P2P_PORT_IN
    read -rp "  RPC port  [26657]: " RPC_PORT_IN
    P2P_PORT=${P2P_PORT_IN:-26656}
    RPC_PORT=${RPC_PORT_IN:-26657}
    echo ""
    info "Ports set — P2P: $P2P_PORT | RPC: $RPC_PORT"

    info "Applying config settings..."
    cd "$GNO_DIR"
    GNOROOT="$GNO_DIR" gnoland config set moniker "$MONIKER"
    warn "About to set p2p.persistent_peers to the value pinned in this script."
    warn "Verify it against the official deployment folder before trusting it:"
    warn "  gnolang/gno, branch chain/mainnet, misc/deployments/mainnet.gno.land/"
    read -rp "  Use pinned peers as-is? [y/N] (N lets you paste your own): " USE_PINNED_PEERS
    if [[ "$USE_PINNED_PEERS" =~ ^[Yy]$ ]]; then
        FINAL_PEERS="$PERSISTENT_PEERS"
    else
        read -rp "  Paste verified persistent_peers value: " FINAL_PEERS
    fi
    GNOROOT="$GNO_DIR" gnoland config set p2p.persistent_peers "$FINAL_PEERS"
    GNOROOT="$GNO_DIR" gnoland config set p2p.external_address "${SERVER_IP}:${P2P_PORT}"
    GNOROOT="$GNO_DIR" gnoland config set p2p.laddr "tcp://0.0.0.0:${P2P_PORT}"
    GNOROOT="$GNO_DIR" gnoland config set rpc.laddr "tcp://127.0.0.1:${RPC_PORT}"
    GNOROOT="$GNO_DIR" gnoland config set application.prune_strategy syncable
    GNOROOT="$GNO_DIR" gnoland config set consensus.timeout_commit 3s
    GNOROOT="$GNO_DIR" gnoland config set consensus.peer_gossip_sleep_duration 10ms
    GNOROOT="$GNO_DIR" gnoland config set p2p.flush_throttle_timeout 10ms
    GNOROOT="$GNO_DIR" gnoland config set mempool.size 10000
    GNOROOT="$GNO_DIR" gnoland config set p2p.max_num_outbound_peers 40
    GNOROOT="$GNO_DIR" gnoland config set p2p.pex true
    success "Config applied."
    info "NOTE: unlike the testnet script, chain-wide consensus parameters here"
    info "(timeout_commit, prune_strategy, etc.) are carried over unverified from"
    info "the testnet script. Confirm these against official mainnet guidance —"
    info "a mismatched consensus-affecting setting can cause you to fall out of"
    info "sync or vote incorrectly."

    # ── Systemd service ───────────────────────────────────────────────────────
    info "Creating systemd service..."
    GNOLAND_BIN=$(gnoland_bin)
    sudo tee "$SERVICE_FILE" > /dev/null <<EOF
[Unit]
Description=Gnoland Mainnet Node
After=network-online.target
Wants=network-online.target

[Service]
User=$USER
WorkingDirectory=$GNO_DIR
Environment=GNOROOT=$GNO_DIR
Environment=HOME=$HOME
ExecStart=$GNOLAND_BIN start \\
  --chainid $CHAIN_ID \\
  --genesis $GNO_DIR/genesis.json
Restart=on-failure
RestartSec=5s
LimitNOFILE=65535
StandardOutput=journal
StandardError=journal
SyslogIdentifier=gnoland-mainnet
EOF
    # NOTE: --skip-genesis-sig-verification is intentionally NOT included by
    # default here. Pearl needed it because of specific placeholder-signed
    # genesis txs (e.g. names.Enable) documented for that testnet. Whether
    # mainnet's genesis needs the same flag has not been confirmed — check
    # the official mainnet release notes / join instructions. If `gnoland
    # start` panics on a signature-verification error at genesis, THAT is
    # your signal to add the flag, not the other way around.
    echo "" | sudo tee -a "$SERVICE_FILE" > /dev/null
    sudo tee -a "$SERVICE_FILE" > /dev/null <<EOF
[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable gnoland-mainnet
    success "Systemd service created and enabled."

    echo ""
    echo -e "  ${BOLD}Installation complete!${NC}"
    echo ""
    echo "  Next steps:"
    echo "  → Verify the genesis hash and peers you just used against the"
    echo "    official gnolang/gno chain/mainnet release page."
    echo "  → Option [4] Load snapshot   (only from a source YOU have verified)"
    echo "  → Option [7] Service management → Start node"
    echo "  → Option [2] Check sync status"
    press_enter
}

# ══════════════════════════════════════════════════════════════════════════════
# 2. CHECK SYNC STATUS
# ══════════════════════════════════════════════════════════════════════════════
check_sync() {
    banner
    echo -e "  ${BOLD}[2] Sync Status${NC}\n"

    STATUS=$(curl -s "http://127.0.0.1:${RPC_PORT}/status" 2>/dev/null || true)

    if [[ -z "$STATUS" ]]; then
        warn "Cannot reach node at port $RPC_PORT."
        echo "  → Is the node running? Check: sudo systemctl status gnoland-mainnet"
    else
        CATCHING_UP=$(echo "$STATUS" | python3 -c \
            "import sys,json; d=json.load(sys.stdin)['result']['sync_info']; print(d['catching_up'])" 2>/dev/null || echo "unknown")
        HEIGHT=$(echo "$STATUS" | python3 -c \
            "import sys,json; d=json.load(sys.stdin)['result']['sync_info']; print(d['latest_block_height'])" 2>/dev/null || echo "unknown")
        TIME=$(echo "$STATUS" | python3 -c \
            "import sys,json; d=json.load(sys.stdin)['result']['sync_info']; print(d['latest_block_time'][:19])" 2>/dev/null || echo "unknown")
        NODE_CHAIN=$(echo "$STATUS" | python3 -c \
            "import sys,json; d=json.load(sys.stdin)['result']['node_info']; print(d['network'])" 2>/dev/null || echo "unknown")

        echo "  Reported chain ID   : $NODE_CHAIN"
        if [[ "$NODE_CHAIN" != "$CHAIN_ID" && "$NODE_CHAIN" != "unknown" ]]; then
            warn "This does not match the expected chain id ($CHAIN_ID)!"
        fi
        echo "  Latest block height : $HEIGHT"
        echo "  Latest block time   : $TIME"

        if [[ "$CATCHING_UP" == "False" ]]; then
            echo -e "  Catching up         : ${GREEN}No — fully synced ✓${NC}"
        else
            echo -e "  Catching up         : ${YELLOW}Yes — still syncing...${NC}"
        fi
    fi

    echo ""
    echo "  Validator key info:"
    cd "$GNO_DIR" 2>/dev/null && GNOROOT="$GNO_DIR" gnoland secrets get validator_key 2>/dev/null || \
        warn "Could not read validator key. Is node initialized?"

    press_enter
}

# ══════════════════════════════════════════════════════════════════════════════
# 3. WALLET MENU
# ══════════════════════════════════════════════════════════════════════════════
wallet_menu() {
    while true; do
        banner
        echo -e "  ${BOLD}[3] Wallet${NC}\n"
        echo "  [1] Create new wallet"
        echo "  [2] Recover wallet from mnemonic"
        echo "  [3] List wallets"
        echo "  [0] Back"
        echo ""
        read -rp "  Choose: " choice

        case "$choice" in
            1) wallet_create ;;
            2) wallet_recover ;;
            3) wallet_list ;;
            0) return ;;
            *) warn "Invalid option."; sleep 1 ;;
        esac
    done
}

wallet_create() {
    banner
    echo -e "  ${BOLD}Create New Wallet${NC}\n"
    require_cmd gnokey

    read -rp "  Enter key name: " KEY_NAME
    [[ -z "$KEY_NAME" ]] && { warn "Key name cannot be empty."; press_enter; return; }

    echo ""
    warn "This wallet can hold REAL GNOT. You will be shown a 24-word mnemonic."
    warn "Write it down offline and store it safely. It CANNOT be recovered if"
    warn "lost, and anyone who obtains it can take your funds."
    press_enter

    gnokey add "$KEY_NAME"

    echo ""
    success "Wallet '$KEY_NAME' created."
    press_enter
}

wallet_recover() {
    banner
    echo -e "  ${BOLD}Recover Wallet from Mnemonic${NC}\n"
    require_cmd gnokey

    read -rp "  Enter key name: " KEY_NAME
    [[ -z "$KEY_NAME" ]] && { warn "Key name cannot be empty."; press_enter; return; }

    echo ""
    info "You will be prompted for your mnemonic phrase."
    gnokey add "$KEY_NAME" --recover

    echo ""
    success "Wallet '$KEY_NAME' recovered."
    press_enter
}

wallet_list() {
    banner
    echo -e "  ${BOLD}Wallets${NC}\n"
    require_cmd gnokey
    gnokey list
    press_enter
}

# ══════════════════════════════════════════════════════════════════════════════
# 4. LOAD SNAPSHOT
# ══════════════════════════════════════════════════════════════════════════════
load_snapshot() {
    banner
    echo -e "  ${BOLD}[4] Load Snapshot${NC}\n"

    if [[ -z "$SNAPSHOT_URL" ]]; then
        warn "No snapshot URL is configured."
        echo ""
        read -rp "  Paste a snapshot URL you have personally verified (or leave blank to cancel): " USER_SNAPSHOT
        [[ -z "$USER_SNAPSHOT" ]] && { info "Cancelled."; press_enter; return; }
        SNAPSHOT_URL="$USER_SNAPSHOT"
    fi

    require_cmd lz4

    echo "  Snapshot source: $SNAPSHOT_URL"
    warn "This URL and its fallback checksum came from a screenshot/JSON the"
    warn "user pasted in chat, NOT from Claude independently fetching and"
    warn "validating the host. Treat it with the same caution as any"
    warn "third-party binary download."
    echo ""

    # Try to get a *fresh* per-generation checksum before trusting the fixed
    # fallback baked into this script — the file is periodically
    # regenerated (a new blockHeight/sha256 each time), so a hardcoded
    # checksum goes stale. This tries a couple of conventional metadata
    # locations; neither is confirmed to actually exist on this host.
    FRESH_SHA256=""
    for META_URL in "${SNAPSHOT_URL%.tar.lz4}.json" "$(dirname "$SNAPSHOT_URL")/metadata.json"; do
        META_JSON=$(curl -fsSL --max-time 10 "$META_URL" 2>/dev/null || true)
        if [[ -n "$META_JSON" ]]; then
            CANDIDATE=$(echo "$META_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('sha256',''))" 2>/dev/null || true)
            if [[ -n "$CANDIDATE" ]]; then
                FRESH_SHA256="$CANDIDATE"
                info "Fetched fresh metadata from $META_URL"
                break
            fi
        fi
    done

    if [[ -n "$FRESH_SHA256" ]]; then
        EXPECTED_SHA256="$FRESH_SHA256"
        success "Using freshly-fetched checksum: $EXPECTED_SHA256"
    else
        warn "Could not fetch fresh per-generation metadata from any known location."
        warn "Falling back to the fixed checksum pasted in chat, which is ONLY"
        warn "valid for the generation reported as of 2026-09-23 (block 261400):"
        warn "  $SNAPSHOT_FALLBACK_SHA256"
        warn "If the host has since published a newer snapshot, this WILL mismatch"
        warn "— which is actually the safe outcome (the script aborts rather than"
        warn "loading unverified data)."
        read -rp "  Use this fallback checksum? [y/N]: " USE_FALLBACK
        if [[ "$USE_FALLBACK" =~ ^[Yy]$ ]]; then
            EXPECTED_SHA256="$SNAPSHOT_FALLBACK_SHA256"
        else
            read -rp "  Paste a checksum you've verified yourself (or leave blank to cancel): " EXPECTED_SHA256
            [[ -z "$EXPECTED_SHA256" ]] && { info "Cancelled."; press_enter; return; }
        fi
    fi

    echo ""
    warn "This will DELETE existing chain data (db and wal)."
    warn "Your keys, config, and secrets will NOT be touched."
    echo ""
    read -rp "  Continue? [y/N]: " CONFIRM
    [[ "$CONFIRM" =~ ^[Yy]$ ]] || { info "Aborted."; press_enter; return; }

    info "Stopping gnoland-mainnet service..."
    sudo systemctl stop gnoland-mainnet 2>/dev/null || pkill -f "gnoland start" 2>/dev/null || true
    sleep 2

    TMP_SNAPSHOT="/tmp/gnoland-mainnet-snapshot.tar.lz4"
    info "Downloading snapshot to $TMP_SNAPSHOT (this may take a while)..."
    echo ""
    if command -v pv &>/dev/null; then
        curl -L "$SNAPSHOT_URL" | pv > "$TMP_SNAPSHOT"
    else
        curl -L --progress-bar "$SNAPSHOT_URL" -o "$TMP_SNAPSHOT"
    fi

    info "Verifying checksum..."
    ACTUAL_SNAPSHOT_SHA=$(shasum -a 256 "$TMP_SNAPSHOT" | awk '{print $1}')
    if [[ "$ACTUAL_SNAPSHOT_SHA" != "$EXPECTED_SHA256" ]]; then
        rm -f "$TMP_SNAPSHOT"
        die "Snapshot checksum mismatch!\n  Expected: $EXPECTED_SHA256\n  Got:      $ACTUAL_SNAPSHOT_SHA\n  Refusing to load this data. Do NOT retry with checksum verification disabled."
    fi
    success "Snapshot checksum verified."

    info "Clearing old chain data..."
    rm -rf "$DATA_DIR/db" "$DATA_DIR/wal"
    mkdir -p "$DATA_DIR"
    success "Old data cleared."

    info "Extracting snapshot..."
    lz4 -dc "$TMP_SNAPSHOT" | tar -xf - -C "$DATA_DIR"
    rm -f "$TMP_SNAPSHOT"

    echo ""
    success "Snapshot loaded."
    echo ""
    echo "  Data directory contents:"
    ls -lh "$DATA_DIR/" 2>/dev/null || true

    echo ""
    echo "  Start the node via option [7] Service management → Start, then"
    echo "  double-check option [2] Check sync status reports the correct chain id."
    press_enter
}

# ══════════════════════════════════════════════════════════════════════════════
# 5. ADD / UPDATE DESCRIPTION
# ══════════════════════════════════════════════════════════════════════════════
update_description() {
    banner
    echo -e "  ${BOLD}[5] Add / Update Description${NC}\n"
    require_cmd gnokey

    echo "  Available wallets:"
    gnokey list
    echo ""
    read -rp "  Enter key name: " KEY_NAME
    [[ -z "$KEY_NAME" ]] && { warn "Key name cannot be empty."; press_enter; return; }

    OPERATOR_ADDR=$(gnokey list 2>/dev/null | grep "^[0-9]" | grep "$KEY_NAME" | \
        grep -oP 'addr: \K[^ ]+' || true)

    if [[ -z "$OPERATOR_ADDR" ]]; then
        read -rp "  Enter your g1... operator address manually: " OPERATOR_ADDR
    fi

    echo ""
    echo "  Enter your description."
    echo "  Limit: $DESCRIPTION_MAX characters. Markdown is supported."
    echo "  Type your description below, then press Ctrl+D when done:"
    echo "  ─────────────────────────────────────────────────────────"
    DESCRIPTION=$(cat)

    DESC_LEN=${#DESCRIPTION}
    echo ""
    info "Description length: $DESC_LEN / $DESCRIPTION_MAX characters"

    if [[ $DESC_LEN -gt $DESCRIPTION_MAX ]]; then
        error "Description exceeds $DESCRIPTION_MAX character limit ($DESC_LEN chars)."
        error "Please shorten your description and try again."
        press_enter
        return
    fi

    if [[ $DESC_LEN -eq 0 ]]; then
        warn "Description is empty. Aborting."
        press_enter
        return
    fi

    echo ""
    echo "  Preview (first 200 chars):"
    echo "  ${DESCRIPTION:0:200}..."
    echo ""
    warn "This submits a real transaction and spends real gas."
    read -rp "  Submit this description? [y/N]: " CONFIRM
    [[ "$CONFIRM" =~ ^[Yy]$ ]] || { info "Aborted."; press_enter; return; }

    gnokey maketx call \
        --pkgpath "$VALOPERS_PKGPATH" \
        --func "UpdateDescription" \
        --args "$OPERATOR_ADDR" \
        --args "$DESCRIPTION" \
        --gas-fee 1000000ugnot \
        --gas-wanted 50000000 \
        --chainid "$CHAIN_ID" \
        --remote "$RPC_REMOTE" \
        --broadcast \
        "$KEY_NAME"

    echo ""
    success "Description updated."
    press_enter
}

# ══════════════════════════════════════════════════════════════════════════════
# 6. REGISTER VALIDATOR CANDIDATE
# ══════════════════════════════════════════════════════════════════════════════
register_validator() {
    banner
    echo -e "  ${BOLD}[6] Register Validator Candidate${NC}\n"
    warn "This only registers you as a CANDIDATE. On mainnet, being seated in"
    warn "the active validator set additionally requires a GovDAO member to"
    warn "submit and pass a proposal on your behalf — it is not automatic and"
    warn "is not guaranteed. This transaction also spends real GNOT on gas,"
    warn "and there is no faucet to replace it if something goes wrong."
    press_enter
    require_cmd gnokey

    CATCHING_UP=$(curl -s "http://127.0.0.1:${RPC_PORT}/status" 2>/dev/null | \
        python3 -c "import sys,json; print(json.load(sys.stdin)['result']['sync_info']['catching_up'])" 2>/dev/null || echo "unknown")

    if [[ "$CATCHING_UP" == "True" ]]; then
        warn "Node is still syncing. It is strongly recommended to wait until fully synced."
        read -rp "  Continue anyway? [y/N]: " CONT
        [[ "$CONT" =~ ^[Yy]$ ]] || { press_enter; return; }
    fi

    info "Reading consensus public key..."
    cd "$GNO_DIR"
    VALIDATOR_INFO=$(GNOROOT="$GNO_DIR" gnoland secrets get validator_key 2>/dev/null || true)
    CONSENSUS_PUBKEY=$(echo "$VALIDATOR_INFO" | python3 -c \
        "import sys,json; print(json.load(sys.stdin)['pub_key'])" 2>/dev/null || true)

    if [[ -z "$CONSENSUS_PUBKEY" ]]; then
        warn "Could not auto-detect consensus pubkey."
        read -rp "  Enter your gpub1... consensus pubkey manually: " CONSENSUS_PUBKEY
    else
        info "Consensus pubkey: $CONSENSUS_PUBKEY"
    fi

    echo ""
    echo "  Available wallets:"
    gnokey list
    echo ""
    read -rp "  Enter key name (operator wallet): " KEY_NAME
    [[ -z "$KEY_NAME" ]] && { warn "Key name cannot be empty."; press_enter; return; }

    OPERATOR_ADDR=$(gnokey list 2>/dev/null | grep "^[0-9]" | grep "$KEY_NAME" | \
        grep -oP 'addr: \K[^ ]+' || true)

    if [[ -z "$OPERATOR_ADDR" ]]; then
        read -rp "  Enter your g1... operator address manually: " OPERATOR_ADDR
    fi
    info "Operator address: $OPERATOR_ADDR"

    echo ""
    info "Checking balance..."
    BALANCE=$(gnokey query -remote "$RPC_REMOTE" "auth/accounts/$OPERATOR_ADDR" 2>/dev/null | \
        python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('BaseAccount',{}).get('coins','0ugnot'))" 2>/dev/null || echo "unknown")
    info "Balance: $BALANCE"

    if [[ "$BALANCE" == "0ugnot" || "$BALANCE" == "" ]]; then
        warn "Balance is 0. Mainnet has NO faucet — you must acquire real GNOT"
        warn "(exchange, OTC, grant, etc.) and send it to $OPERATOR_ADDR before"
        warn "you can pay for this transaction."
        press_enter
        return
    fi

    echo ""
    read -rp "  Moniker (node display name): " MONIKER
    echo ""
    echo "  Server type options: cloud | on-prem | data-center"
    read -rp "  Server type: " SERVER_TYPE
    echo ""
    echo "  Enter a short description (press Ctrl+D when done):"
    echo "  Note: Full description can be set/updated via option [5]."
    echo "  ─────────────────────────────────────────────────────────"
    DESCRIPTION=$(cat)

    DESC_LEN=${#DESCRIPTION}
    if [[ $DESC_LEN -gt $DESCRIPTION_MAX ]]; then
        error "Description exceeds $DESCRIPTION_MAX characters ($DESC_LEN). Shorten and retry."
        press_enter
        return
    fi

    echo ""
    echo "  ─── Registration summary ────────────────────────────────"
    echo "  Chain           : $CHAIN_ID (MAINNET — real value)"
    echo "  Realm pkgpath   : $VALOPERS_PKGPATH  (VERIFY this is correct for mainnet)"
    echo "  Moniker         : $MONIKER"
    echo "  Operator address: $OPERATOR_ADDR"
    echo "  Consensus pubkey: $CONSENSUS_PUBKEY"
    echo "  Server type     : $SERVER_TYPE"
    echo "  Description     : ${DESCRIPTION:0:80}..."
    echo "  ─────────────────────────────────────────────────────────"
    echo ""
    read -rp "  Submit registration? [y/N]: " CONFIRM
    [[ "$CONFIRM" =~ ^[Yy]$ ]] || { info "Aborted."; press_enter; return; }

    gnokey maketx call \
        --pkgpath "$VALOPERS_PKGPATH" \
        --func Register \
        --args "$MONIKER" \
        --args "$DESCRIPTION" \
        --args "$SERVER_TYPE" \
        --args "$OPERATOR_ADDR" \
        --args "$CONSENSUS_PUBKEY" \
        --gas-fee 1000000ugnot \
        --gas-wanted 50000000 \
        --chainid "$CHAIN_ID" \
        --remote "$RPC_REMOTE" \
        --broadcast \
        "$KEY_NAME"

    echo ""
    success "Registration submitted!"
    echo ""
    echo "  You are now a validator CANDIDATE — not yet active."
    echo "  A GovDAO member must create and pass a proposal to add you to"
    echo "  the active validator set. Reach out through official gno.land"
    echo "  community/governance channels to pursue this."
    echo ""
    echo "  Check your profile (verify the exact explorer path yourself):"
    echo "  $EXPLORER_URL"
    press_enter
}

# ══════════════════════════════════════════════════════════════════════════════
# 7. SERVICE MANAGEMENT
# ══════════════════════════════════════════════════════════════════════════════
service_menu() {
    while true; do
        banner
        echo -e "  ${BOLD}[7] Service Management${NC}\n"

        if systemctl is-active --quiet gnoland-mainnet 2>/dev/null; then
            echo -e "  Status: ${GREEN}● running${NC}"
        else
            echo -e "  Status: ${RED}● stopped${NC}"
        fi
        echo ""
        echo "  [1] Start"
        echo "  [2] Stop"
        echo "  [3] Restart"
        echo "  [4] View live logs (Ctrl+C to exit)"
        echo "  [5] View last 50 log lines"
        echo "  [0] Back"
        echo ""
        read -rp "  Choose: " choice

        case "$choice" in
            1)
                sudo systemctl start gnoland-mainnet
                success "Node started."
                sleep 1
                ;;
            2)
                sudo systemctl stop gnoland-mainnet
                success "Node stopped."
                sleep 1
                ;;
            3)
                sudo systemctl restart gnoland-mainnet
                success "Node restarted."
                sleep 1
                ;;
            4)
                echo ""
                info "Press Ctrl+C to return to menu."
                sleep 1
                sudo journalctl -u gnoland-mainnet -f || true
                ;;
            5)
                echo ""
                sudo journalctl -u gnoland-mainnet -n 50 --no-pager || true
                press_enter
                ;;
            0) return ;;
            *) warn "Invalid option."; sleep 1 ;;
        esac
    done
}

# ══════════════════════════════════════════════════════════════════════════════
# 8. BUILD AND SCHEDULE A COORDINATED MAINNET UPDATE
# ══════════════════════════════════════════════════════════════════════════════
update_node() {
    banner
    echo -e "  ${BOLD}[8] Build and Schedule Node Update${NC}\n"
    echo "  Enter BOTH values from the official upgrade announcement:"
    echo "  - Release version, for example: 1.7.0"
    echo "  - Exact mainnet halt block height, for example: 1183000"
    echo ""
    warn "The height is deliberately manual. It is never guessed from the version."
    echo ""

    require_cmd git
    require_cmd make
    require_cmd go
    require_cmd curl
    require_cmd python3

    local SERVICE="gnoland-mainnet"
    local NODE_GNO_DIR NODE_GNOROOT SERVICE_ENV
    NODE_GNO_DIR="$(sudo systemctl show -p WorkingDirectory --value "$SERVICE")"
    NODE_GNO_DIR="${NODE_GNO_DIR:-$GNO_DIR}"

    # gnoland initializes gnoenv even for `version`; inherit the exact GNOROOT
    # configured for the live systemd service. Fall back to WorkingDirectory,
    # which is the repository root in this install layout.
    SERVICE_ENV="$(sudo systemctl show -p Environment --value "$SERVICE" 2>/dev/null || true)"
    NODE_GNOROOT="$(printf '%s\n' "$SERVICE_ENV" | tr ' ' '\n' | sed -n 's/^GNOROOT=//p' | head -n 1)"
    NODE_GNOROOT="${NODE_GNOROOT:-$NODE_GNO_DIR}"
    if [[ ! -d "$NODE_GNOROOT" ]]; then
        error "GNOROOT directory does not exist: $NODE_GNOROOT"
        press_enter
        return
    fi
    export GNOROOT="$NODE_GNOROOT"

    local CONFIG_FILE="$NODE_GNO_DIR/gnoland-data/config/config.toml"
    local WATCHER_UNIT="gnoland-mainnet-upgrade-watcher.service"
    local WATCHER_SCRIPT="/usr/local/sbin/gnoland-mainnet-upgrade-watcher"
    local WATCHER_CONFIG="/etc/gnoland-mainnet-upgrade.conf"

    if ! sudo systemctl cat "$SERVICE" >/dev/null 2>&1; then
        error "systemd service '$SERVICE' was not found."
        press_enter
        return
    fi

    if ! sudo systemctl is-active --quiet "$SERVICE"; then
        error "The node service must be running before scheduling an update."
        press_enter
        return
    fi

    if sudo systemctl is-active --quiet "$WATCHER_UNIT"; then
        warn "An update watcher is already active."
        echo "  Check: sudo journalctl -u $WATCHER_UNIT -f"
        press_enter
        return
    fi

    if [[ ! -f "$CONFIG_FILE" ]]; then
        error "Config file not found: $CONFIG_FILE"
        press_enter
        return
    fi

    # Resolve the exact executable used by the systemd service.
    local EXECSTART GNOLAND_BIN GNOKEY_BIN SERVICE_USER SERVICE_GROUP
    EXECSTART="$(sudo systemctl show -p ExecStart --value "$SERVICE")"
    GNOLAND_BIN="$(printf '%s\n' "$EXECSTART" | sed -n 's/.*path=\([^ ;}]*\).*/\1/p')"
    if [[ -z "$GNOLAND_BIN" ]]; then
        GNOLAND_BIN="$(gnoland_bin)"
    fi
    if [[ ! -x "$GNOLAND_BIN" ]]; then
        error "Could not locate the gnoland executable used by systemd: $GNOLAND_BIN"
        press_enter
        return
    fi

    GNOKEY_BIN="$(dirname "$GNOLAND_BIN")/gnokey"
    if [[ ! -x "$GNOKEY_BIN" ]]; then
        error "Matching gnokey executable not found: $GNOKEY_BIN"
        press_enter
        return
    fi

    SERVICE_USER="$(sudo systemctl show -p User --value "$SERVICE")"
    SERVICE_USER="${SERVICE_USER:-root}"
    SERVICE_GROUP="$(id -gn "$SERVICE_USER" 2>/dev/null || echo "$SERVICE_USER")"

    # Read the actual local RPC port from config.toml.
    local RPC_PORT
    RPC_PORT="$(python3 - "$CONFIG_FILE" <<'PYRPC'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
section = re.search(r"(?ms)^\[rpc\]\s*(.*?)(?=^\s*\[|\Z)", text)
if not section:
    raise SystemExit("[rpc] section not found")
match = re.search(r'(?m)^\s*laddr\s*=\s*"tcp://[^\"]*:(\d+)"', section.group(1))
if not match:
    raise SystemExit("rpc.laddr port not found")
print(match.group(1))
PYRPC
)" || {
        error "Could not determine RPC port from config.toml."
        press_enter
        return
    }

    # Governance-driven upgrades require config halt_height to remain zero.
    local CONFIG_HALT
    CONFIG_HALT="$(python3 - "$CONFIG_FILE" <<'PYHALT'
import re, sys
value = "0"
for raw in open(sys.argv[1], encoding="utf-8"):
    line = raw.split("#", 1)[0].strip()
    match = re.match(r"^halt_height\s*=\s*(\d+)\s*$", line)
    if match:
        value = match.group(1)
        break
print(value)
PYHALT
)"
    if [[ "$CONFIG_HALT" != "0" ]]; then
        error "config.toml has halt_height=$CONFIG_HALT. For a governance halt this must be 0."
        error "Do not mix a local config halt with the on-chain governance halt."
        press_enter
        return
    fi

    local CURRENT_VERSION
    CURRENT_VERSION="$(GNOROOT="$NODE_GNOROOT" "$GNOLAND_BIN" version 2>&1 || true)"
    echo "  Current binary : $CURRENT_VERSION"
    echo "  RPC endpoint   : http://127.0.0.1:$RPC_PORT/status"
    echo "  Service user   : $SERVICE_USER"
    echo ""

    local TARGET_VERSION TARGET_HEIGHT
    read -rp "  Target version (e.g. 1.7.0): " TARGET_VERSION
    TARGET_VERSION="${TARGET_VERSION#v}"
    if [[ ! "$TARGET_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        error "Invalid version. Use MAJOR.MINOR.PATCH, e.g. 1.7.0"
        press_enter
        return
    fi
    TARGET_VERSION="v$TARGET_VERSION"

    read -rp "  Exact mainnet halt block height: " TARGET_HEIGHT
    if [[ ! "$TARGET_HEIGHT" =~ ^[1-9][0-9]*$ ]]; then
        error "Invalid block height. Enter a positive integer without separators."
        press_enter
        return
    fi

    # Verify local RPC and ensure the requested halt is still ahead (or exactly reached).
    local INITIAL_STATUS INITIAL_CHAIN INITIAL_HEIGHT INITIAL_CATCHING
    INITIAL_STATUS="$(curl -fsS --max-time 10 "http://127.0.0.1:${RPC_PORT}/status" 2>/dev/null || true)"
    if [[ -z "$INITIAL_STATUS" ]]; then
        error "Local RPC is not responding. Update has not been scheduled."
        press_enter
        return
    fi

    INITIAL_CHAIN="$(printf '%s' "$INITIAL_STATUS" | python3 -c 'import json,sys; print(json.load(sys.stdin)["result"]["node_info"]["network"])' 2>/dev/null || true)"
    INITIAL_HEIGHT="$(printf '%s' "$INITIAL_STATUS" | python3 -c 'import json,sys; print(json.load(sys.stdin)["result"]["sync_info"]["latest_block_height"])' 2>/dev/null || true)"
    INITIAL_CATCHING="$(printf '%s' "$INITIAL_STATUS" | python3 -c 'import json,sys; print(json.load(sys.stdin)["result"]["sync_info"]["catching_up"])' 2>/dev/null || true)"
    if [[ "$INITIAL_CHAIN" != "$CHAIN_ID" || ! "$INITIAL_HEIGHT" =~ ^[0-9]+$ ]]; then
        error "Local RPC chain/height check failed. Chain=$INITIAL_CHAIN Height=$INITIAL_HEIGHT"
        press_enter
        return
    fi
    if [[ "$INITIAL_CATCHING" != "False" ]]; then
        error "The node is still catching up. Wait until it is fully synced, then schedule the update."
        press_enter
        return
    fi
    if (( INITIAL_HEIGHT > TARGET_HEIGHT )); then
        error "Your node is already at height $INITIAL_HEIGHT, above the entered halt $TARGET_HEIGHT."
        error "No binary will be changed. Re-check the official halt height."
        press_enter
        return
    fi

    echo ""
    echo "  ─── Update plan ─────────────────────────────────────────"
    echo "  Chain          : $CHAIN_ID"
    echo "  Version        : $TARGET_VERSION"
    echo "  Target halt    : $TARGET_HEIGHT"
    echo "  Current height : $INITIAL_HEIGHT"
    echo "  Poll interval  : 15 seconds"
    echo "  Stability rule : 5 consecutive identical readings"
    echo "  On-chain check : halt_height + halt_min_version must match"
    echo "  RPC monitoring : local RPC + official public RPC fallback"
    echo "  Node action    : keep running until halt, then restart"
    echo "  ─────────────────────────────────────────────────────────"
    echo ""
    warn "The node will continue using its current binary while the new version is built."
    warn "After build, a root-owned systemd watcher waits for the exact height."
    read -rp "  Continue? [y/N]: " CONFIRM
    [[ "$CONFIRM" =~ ^[Yy]$ ]] || { info "Cancelled."; press_enter; return; }

    # Build in a separate checkout; never switch or modify the live repository.
    local STAMP BUILD_ROOT BUILD_DIR SOURCE_DIR BIN_DIR
    STAMP="$(date +%Y%m%d-%H%M%S)"
    BUILD_ROOT="$HOME/.cache/gnoland-mainnet-updates"
    BUILD_DIR="$BUILD_ROOT/${TARGET_VERSION}-${STAMP}"
    SOURCE_DIR="$BUILD_DIR/source"
    BIN_DIR="$BUILD_DIR/bin"
    mkdir -p "$SOURCE_DIR" "$BIN_DIR"

    info "Checking that tag $TARGET_VERSION exists on the official repository..."
    if ! git ls-remote --exit-code --tags https://github.com/gnolang/gno.git "refs/tags/$TARGET_VERSION" >/dev/null 2>&1; then
        error "Tag $TARGET_VERSION was not found on https://github.com/gnolang/gno"
        press_enter
        return
    fi

    info "Cloning $TARGET_VERSION into an isolated build directory..."
    if ! git clone --depth 1 --branch "$TARGET_VERSION" --single-branch \
        https://github.com/gnolang/gno.git "$SOURCE_DIR"; then
        error "Git clone failed. Existing node and binary are untouched."
        press_enter
        return
    fi

    info "Building gnoland and gnokey. Go toolchain auto-download is enabled; global Go is not replaced..."
    if ! (cd "$SOURCE_DIR" && \
        CGO_ENABLED=0 GOTOOLCHAIN=auto GOBIN="$BIN_DIR" make -C gno.land \
            VERSION="$TARGET_VERSION" install.gnoland install.gnokey); then
        error "Build failed. Existing node and binary are untouched."
        echo "  Build directory: $BUILD_DIR"
        press_enter
        return
    fi

    if [[ ! -x "$BIN_DIR/gnoland" || ! -x "$BIN_DIR/gnokey" ]]; then
        error "Build output is incomplete. Existing node and binary are untouched."
        press_enter
        return
    fi

    local BUILT_GNOLAND_VERSION BUILT_GNOKEY_VERSION
    BUILT_GNOLAND_VERSION="$(GNOROOT="$NODE_GNOROOT" "$BIN_DIR/gnoland" version 2>&1 || true)"
    BUILT_GNOKEY_VERSION="$("$BIN_DIR/gnokey" version 2>&1 || true)"
    echo "  Built gnoland: $BUILT_GNOLAND_VERSION"
    echo "  Built gnokey : $BUILT_GNOKEY_VERSION"
    if [[ "$BUILT_GNOLAND_VERSION" != *"$TARGET_VERSION"* || "$BUILT_GNOKEY_VERSION" != *"$TARGET_VERSION"* ]]; then
        error "The compiled binaries do not report $TARGET_VERSION. Not scheduling update."
        press_enter
        return
    fi

    # Copy verified artifacts to root-owned storage so the watcher can safely
    # survive logout/reboot and install only these exact binaries.
    local STAGED_ROOT BACKUP_DIR
    STAGED_ROOT="/var/lib/gnoland-mainnet-updates/${TARGET_VERSION}-${STAMP}"
    BACKUP_DIR="$NODE_GNO_DIR/backups/${TARGET_VERSION}-${STAMP}"
    sudo install -d -o root -g root -m 0755 "$STAGED_ROOT"
    sudo install -o root -g root -m 0755 "$BIN_DIR/gnoland" "$STAGED_ROOT/gnoland"
    sudo install -o root -g root -m 0755 "$BIN_DIR/gnokey" "$STAGED_ROOT/gnokey"

    # Write root-readable watcher settings as shell-escaped assignments.
    {
        printf 'SERVICE_NAME=%q\n' "$SERVICE"
        printf 'SERVICE_USER=%q\n' "$SERVICE_USER"
        printf 'SERVICE_GROUP=%q\n' "$SERVICE_GROUP"
        printf 'TARGET_VERSION=%q\n' "$TARGET_VERSION"
        printf 'TARGET_HEIGHT=%q\n' "$TARGET_HEIGHT"
        printf 'CHECK_INTERVAL=%q\n' "15"
        printf 'RPC_URL=%q\n' "http://127.0.0.1:${RPC_PORT}/status"
        printf 'FALLBACK_RPC_URL=%q\n' "https://rpc.gno.land/status"
        printf 'GOVERNANCE_RPC_URL=%q\n' "https://rpc.gno.land"
        printf 'GNOROOT=%q\n' "$NODE_GNOROOT"
        printf 'GNOLAND_BIN=%q\n' "$GNOLAND_BIN"
        printf 'GNOKEY_BIN=%q\n' "$GNOKEY_BIN"
        printf 'STAGED_GNOLAND=%q\n' "$STAGED_ROOT/gnoland"
        printf 'STAGED_GNOKEY=%q\n' "$STAGED_ROOT/gnokey"
        printf 'BACKUP_DIR=%q\n' "$BACKUP_DIR"
        printf 'WATCHER_UNIT=%q\n' "$WATCHER_UNIT"
    } | sudo tee "$WATCHER_CONFIG" >/dev/null
    sudo chmod 0600 "$WATCHER_CONFIG"

    # Root-owned watcher: it monitors local RPC and falls back to official public RPC.
    sudo tee "$WATCHER_SCRIPT" >/dev/null <<'WATCHER'
#!/usr/bin/env bash
set -Eeuo pipefail

CONFIG="/etc/gnoland-mainnet-upgrade.conf"
[[ -r "$CONFIG" ]] || { echo "[ERROR] Missing $CONFIG"; exit 1; }
# shellcheck disable=SC1090
source "$CONFIG"
# gnoland/gnokey may consult gnoenv even for simple commands.
export GNOROOT

log() { echo "[$(date '+%F %T')] $*"; }
stop_watcher_on_error() {
    systemctl disable "$WATCHER_UNIT" >/dev/null 2>&1 || true
}
fail() {
    log "ERROR: $*"
    stop_watcher_on_error
    exit 1
}

rpc_fields_from() {
    local endpoint="$1" raw
    raw="$(curl -fsS --connect-timeout 3 --max-time 8 "$endpoint" 2>/dev/null)" || return 1
    printf '%s' "$raw" | python3 -c '
import json,sys
r=json.load(sys.stdin)["result"]
s=r["sync_info"]
n=r["node_info"]
print("\t".join([
    str(n.get("network", "")),
    str(s.get("latest_block_height", "")),
    str(s.get("catching_up", "")),
    str(r.get("build_version", "")),
]))
' 2>/dev/null
}

# Prefer the local RPC; fall back to the official endpoint if the old binary
# exits at the governance halt and can no longer serve local RPC requests.
rpc_fields() {
    local fields
    if fields="$(rpc_fields_from "$RPC_URL" 2>/dev/null)" && [[ -n "$fields" ]]; then
        printf '%s\n' "$fields"
        return 0
    fi
    if fields="$(rpc_fields_from "$FALLBACK_RPC_URL" 2>/dev/null)" && [[ -n "$fields" ]]; then
        printf '%s\n' "$fields"
        return 0
    fi
    return 1
}

# These on-chain values are authoritative. The manually entered version and
# height must agree with the governance proposal before the node is restarted.
query_data_value() {
    local query_path="$1" output
    output="$("$STAGED_GNOKEY" query "$query_path" -remote "$GOVERNANCE_RPC_URL" 2>&1)" || return 1
    printf '%s\n' "$output" | sed -n 's/^[[:space:]]*data:[[:space:]]*//p' | head -n 1 | tr -d '"()' | awk '{print $1}'
}

verify_governance_halt() {
    local onchain_height onchain_version
    onchain_height="$(query_data_value 'params/node:p:halt_height' || true)"
    onchain_version="$(query_data_value 'params/node:p:halt_min_version' || true)"

    if [[ "$onchain_height" =~ ^[0-9]+$ ]] && (( onchain_height > 0 )); then
        if [[ "$onchain_height" != "$TARGET_HEIGHT" ]]; then
            fail "Manual halt height $TARGET_HEIGHT does not match on-chain governance halt $onchain_height. No binary changed."
        fi
        if [[ "$onchain_version" != "$TARGET_VERSION" ]]; then
            fail "Manual version $TARGET_VERSION does not match on-chain halt_min_version '$onchain_version'. No binary changed."
        fi
        return 0
    fi
    return 1
}

log "Watcher started. Target=$TARGET_VERSION halt_height=$TARGET_HEIGHT local_RPC=$RPC_URL fallback_RPC=$FALLBACK_RPC_URL"
log "The node remains on its existing binary until the exact halt height is stable."

LAST_HEIGHT=""
STABLE_COUNT=0
LOOP_COUNT=0

GOVERNANCE_CONFIRM_COUNT=0

while true; do
    RPC_SOURCE="local"
    FIELDS="$(rpc_fields_from "$RPC_URL" 2>/dev/null || true)"
    if [[ -z "$FIELDS" ]]; then
        RPC_SOURCE="official-fallback"
        FIELDS="$(rpc_fields_from "$FALLBACK_RPC_URL" 2>/dev/null || true)"
    fi
    if [[ -z "$FIELDS" ]]; then
        STABLE_COUNT=0
        LAST_HEIGHT=""
        log "Local and official fallback RPC are unavailable; retrying."
        sleep "$CHECK_INTERVAL"
        continue
    fi

    if [[ "$RPC_SOURCE" == "official-fallback" ]] && ! systemctl is-active --quiet "$SERVICE_NAME"; then
        log "Node service is stopped/restarting; monitoring the official RPC fallback."
    fi

    IFS=$'\t' read -r CHAIN HEIGHT CATCHING_UP BUILD_VERSION <<< "$FIELDS"
    if [[ "$CHAIN" != "gnoland-1" ]]; then
        fail "RPC returned unexpected chain ID '$CHAIN'. No restart performed."
    fi
    if [[ ! "$HEIGHT" =~ ^[0-9]+$ ]]; then
        STABLE_COUNT=0
        LAST_HEIGHT=""
        log "RPC returned an invalid height '$HEIGHT'; retrying."
        sleep "$CHECK_INTERVAL"
        continue
    fi

    # Before the halt, periodically validate the manually entered values.
    # At/after the halt, governance must confirm the exact version and height.
    if (( LOOP_COUNT % 4 == 0 )) || (( HEIGHT >= TARGET_HEIGHT )); then
        if (( HEIGHT >= TARGET_HEIGHT )); then
            verify_governance_halt || fail "Could not confirm on-chain halt_height/halt_min_version. Refusing to restart."
        else
            verify_governance_halt || true
        fi
    fi

    if (( HEIGHT == TARGET_HEIGHT )) && [[ "$CATCHING_UP" == "False" ]]; then
        GOVERNANCE_CONFIRM_COUNT=0
        if [[ "$HEIGHT" == "$LAST_HEIGHT" ]]; then
            STABLE_COUNT=$((STABLE_COUNT + 1))
        else
            LAST_HEIGHT="$HEIGHT"
            STABLE_COUNT=1
        fi
        log "Halt height confirmed: $HEIGHT; identical stable reading ${STABLE_COUNT}/5 ($RPC_SOURCE RPC)."
        if (( STABLE_COUNT >= 5 )); then
            verify_governance_halt || fail "Could not confirm on-chain halt_height/halt_min_version. Refusing to restart."
            break
        fi
    elif (( HEIGHT > TARGET_HEIGHT )) && [[ "$CATCHING_UP" == "False" ]]; then
        # Network has resumed beyond the halt: waiting for the old block to
        # repeat is impossible, so require five repeated governance matches.
        STABLE_COUNT=0
        LAST_HEIGHT=""
        GOVERNANCE_CONFIRM_COUNT=$((GOVERNANCE_CONFIRM_COUNT + 1))
        log "Network is beyond halt height ($HEIGHT > $TARGET_HEIGHT); governance confirmation ${GOVERNANCE_CONFIRM_COUNT}/5 ($RPC_SOURCE RPC)."
        if (( GOVERNANCE_CONFIRM_COUNT >= 5 )); then
            break
        fi
    else
        LAST_HEIGHT=""
        STABLE_COUNT=0
        GOVERNANCE_CONFIRM_COUNT=0
        LOOP_COUNT=$((LOOP_COUNT + 1))
        if (( LOOP_COUNT % 4 == 0 )); then
            log "Waiting for halt height $TARGET_HEIGHT; current=$HEIGHT catching_up=$CATCHING_UP ($RPC_SOURCE RPC)."
        fi
    fi

    sleep "$CHECK_INTERVAL"
done

# Final RPC + governance check before stopping the service.
FINAL_FIELDS="$(rpc_fields || true)"
[[ -n "$FINAL_FIELDS" ]] || fail "Local and official fallback RPC stopped responding before restart."
IFS=$'\t' read -r FINAL_CHAIN FINAL_HEIGHT FINAL_CATCHING FINAL_BUILD <<< "$FINAL_FIELDS"
[[ "$FINAL_CHAIN" == "gnoland-1" && "$FINAL_HEIGHT" =~ ^[0-9]+$ ]] || \
    fail "Final pre-stop RPC check failed (chain=$FINAL_CHAIN height=$FINAL_HEIGHT)."
(( FINAL_HEIGHT >= TARGET_HEIGHT )) || fail "Final pre-stop height $FINAL_HEIGHT is below target $TARGET_HEIGHT."
[[ "$FINAL_CATCHING" == "False" ]] || fail "Final pre-stop RPC reports catching_up=$FINAL_CATCHING."
verify_governance_halt || fail "Final governance halt/version check failed."

log "Validated halt condition and governance parameters. Stopping $SERVICE_NAME..."
systemctl stop "$SERVICE_NAME"
if systemctl is-active --quiet "$SERVICE_NAME"; then
    fail "Could not stop $SERVICE_NAME."
fi

mkdir -p "$BACKUP_DIR"
chmod 0700 "$BACKUP_DIR"
cp -a "$GNOLAND_BIN" "$BACKUP_DIR/gnoland.before"
cp -a "$GNOKEY_BIN" "$BACKUP_DIR/gnokey.before"
log "Old binaries backed up to $BACKUP_DIR"

# Stage both replacements before moving either one into place.
install -o "$SERVICE_USER" -g "$SERVICE_GROUP" -m 0755 "$STAGED_GNOLAND" "${GNOLAND_BIN}.new"
install -o "$SERVICE_USER" -g "$SERVICE_GROUP" -m 0755 "$STAGED_GNOKEY" "${GNOKEY_BIN}.new"
[[ "$(GNOROOT="$GNOROOT" "${GNOLAND_BIN}.new" version 2>&1)" == *"$TARGET_VERSION"* ]] || fail "Staged gnoland binary version mismatch."
[[ "$(GNOROOT="$GNOROOT" "${GNOKEY_BIN}.new" version 2>&1)" == *"$TARGET_VERSION"* ]] || fail "Staged gnokey binary version mismatch."

mv -f "${GNOLAND_BIN}.new" "$GNOLAND_BIN"
mv -f "${GNOKEY_BIN}.new" "$GNOKEY_BIN"
log "Installed $TARGET_VERSION binaries."

# Disable before starting the new node so the watcher never re-runs on reboot.
systemctl disable "$WATCHER_UNIT" >/dev/null 2>&1 || true
systemctl start "$SERVICE_NAME"

log "Waiting for systemd and RPC to confirm the new binary..."
READY=0
for _ in $(seq 1 60); do
    if ! systemctl is-active --quiet "$SERVICE_NAME"; then
        log "Node service is not active yet; recent node logs follow."
        journalctl -u "$SERVICE_NAME" -n 40 --no-pager || true
        sleep 5
        continue
    fi
    FIELDS="$(rpc_fields_from "$RPC_URL" 2>/dev/null || true)"
    if [[ -n "$FIELDS" ]]; then
        IFS=$'\t' read -r CHAIN HEIGHT CATCHING_UP BUILD_VERSION <<< "$FIELDS"
        if [[ "$CHAIN" == "gnoland-1" && "$BUILD_VERSION" == "$TARGET_VERSION" ]]; then
            READY=1
            log "RPC confirms build_version=$BUILD_VERSION at height=$HEIGHT catching_up=$CATCHING_UP"
            break
        fi
    fi
    sleep 5
done

if (( READY == 1 )); then
    log "SUCCESS: $SERVICE_NAME is running with $TARGET_VERSION."
    log "Backup: $BACKUP_DIR"
    log "Blockchain data, genesis, config and validator secrets were not modified."
else
    log "WARNING: binaries were replaced and service start was requested, but RPC did not confirm $TARGET_VERSION within 5 minutes."
    log "Inspect: journalctl -u $SERVICE_NAME -n 150 --no-pager"
    journalctl -u "$SERVICE_NAME" -n 100 --no-pager || true
    exit 1
fi
WATCHER
    sudo chmod 0755 "$WATCHER_SCRIPT"
    sudo chown root:root "$WATCHER_SCRIPT"

    sudo tee "/etc/systemd/system/$WATCHER_UNIT" >/dev/null <<'UNIT'
[Unit]
Description=Wait for Gnoland mainnet halt and install prepared upgrade
Wants=network-online.target
After=network-online.target gnoland-mainnet.service

[Service]
Type=simple
ExecStart=/usr/local/sbin/gnoland-mainnet-upgrade-watcher
Restart=no
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
UNIT

    sudo systemctl daemon-reload
    if ! sudo systemd-analyze verify "/etc/systemd/system/$WATCHER_UNIT"; then
        error "The generated watcher unit failed systemd validation."
        press_enter
        return
    fi
    sudo systemctl enable --now "$WATCHER_UNIT"

    echo ""
    success "Build completed and automatic halt watcher is active."
    echo "  Target version : $TARGET_VERSION"
    echo "  Halt height    : $TARGET_HEIGHT"
    echo "  Current node   : still running with the old binary"
    echo "  Watcher        : $WATCHER_UNIT"
    echo "  Build files    : $BUILD_DIR"
    echo "  Staged binary  : $STAGED_ROOT"
    echo ""
    echo "  Follow progress:"
    echo "  sudo journalctl -u $WATCHER_UNIT -f"
    echo ""
    echo "  The watcher survives SSH disconnects and server reboot."
    press_enter
}

update_watcher_status() {
    banner
    echo -e "  ${BOLD}[9] Update Watcher Status / Logs${NC}\n"
    sudo systemctl status gnoland-mainnet-upgrade-watcher.service --no-pager -l || true
    echo ""
    echo "  Recent watcher logs:"
    sudo journalctl -u gnoland-mainnet-upgrade-watcher.service -n 60 --no-pager || true
    press_enter
}

# ══════════════════════════════════════════════════════════════════════════════
# ENTRY POINT
# ══════════════════════════════════════════════════════════════════════════════
main_menu
