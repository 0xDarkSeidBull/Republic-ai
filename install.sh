# Republic-ai#!/bin/bash

# --- COLOR CODES ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# --- HEADER ---
clear
echo -e "${BLUE}=================================================${NC}"
echo -e "${GREEN}    REPUBLIC PROTOCOL AUTO-INSTALLER BY [TERA NAAM] ${NC}"
echo -e "${BLUE}=================================================${NC}"

# --- MENU FUNCTION ---
show_menu() {
    echo -e "\n${YELLOW}CHOOSE AN OPTION:${NC}"
    echo -e "1) 🚀 Install & Run Node (Fresh Start)"
    echo -e "2) 🔑 Create New Wallet & Backup"
    echo -e "3) 📊 Check Sync Status (Catching Up?)"
    echo -e "4) 🛡️ Create Validator (Only after Sync)"
    echo -e "5) 🔍 Check Validator Status"
    echo -e "6) 💰 Check Wallet Balance"
    echo -e "7) ❌ Exit"
    read -p "Enter choice [1-7]: " opt
}

# --- 1. INSTALL NODE ---
install_node() {
    echo -e "${YELLOW}Step 0: Cleaning old files...${NC}"
    sudo systemctl stop republicd 2>/dev/null || true
    pkill republicd 2>/dev/null || true
    rm -rf $HOME/.republic
    sudo rm -f /usr/local/bin/republicd

    echo -e "${YELLOW}Step 1: Installing Dependencies & Go...${NC}"
    sudo apt update && sudo apt install curl jq lz4 build-essential -y
    cd $HOME
    wget -q "https://go.dev/dl/go1.22.5.linux-amd64.tar.gz" && sudo tar -C /usr/local -xzf go1.22.5.linux-amd64.tar.gz
    export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin
    echo "export PATH=\$PATH:/usr/local/go/bin:\$HOME/go/bin" >> $HOME/.bash_profile
    source $HOME/.bash_profile

    echo -e "${YELLOW}Step 2: Downloading Binary v0.3.0...${NC}"
    wget -q https://github.com/RepublicAI/networks/releases/download/v0.3.0/republicd-linux-amd64 -O republicd
    chmod +x republicd && sudo mv republicd /usr/local/bin/republicd

    echo -e "${YELLOW}Step 3: Initializing Node & Snapshot...${NC}"
    republicd init "MyNode" --chain-id raitestnet_77701-1
    curl -L https://raw.githubusercontent.com/RepublicAI/networks/main/testnet/genesis.json -o $HOME/.republic/config/genesis.json
    
    # Auto-Peer Detection
    PEERS=$(curl -sS https://rpc-t.republic.vinjan-inc.com/net_info | jq -r '.result.peers[] | "\(.node_info.id)@\(.remote_ip):\(.node_info.listen_addr)"' | awk -F ':' '{print $1":"$(NF)}' | paste -sd "," -)
    sed -i "s/^persistent_peers *=.*/persistent_peers = \"$PEERS\"/" $HOME/.republic/config/config.toml
    sed -i 's/^indexer *=.*/indexer = "null"/' $HOME/.republic/config/config.toml

    # Snapshot for instant sync
    curl -L https://snapshot.vinjan-inc.com/republic/latest.tar.lz4 | lz4 -dc - | tar -xf - -C $HOME/.republic

    echo -e "${YELLOW}Step 4: Creating Systemd Service...${NC}"
    sudo tee /etc/systemd/system/republicd.service > /dev/null <<EOF
[Unit]
Description=Republic Node
After=network-online.target
[Service]
User=$USER
ExecStart=$(which republicd) start
Restart=always
RestartSec=3
LimitNOFILE=65535
[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload && sudo systemctl enable republicd && sudo systemctl start republicd
    echo -e "${GREEN}✅ Node is running in background!${NC}"
}

# --- LOOP MENU ---
while true; do
    show_menu
    case $opt in
        1) install_node ;;
        2) 
            echo -e "${YELLOW}Creating Wallet... SAVE THE MNEMONIC!${NC}"
            republicd keys add wallet
            ;;
        3) 
            STATUS=$(republicd status 2>/dev/null | jq -r '.sync_info.catching_up')
            HEIGHT=$(republicd status 2>/dev/null | jq -r '.sync_info.latest_block_height')
            if [ "$STATUS" == "false" ]; then
                echo -e "${GREEN}SYNC SUCCESSFULL: Node is fully synced at height $HEIGHT!${NC}"
            else
                echo -e "${RED}SYNCING: Still catching up... Current height: $HEIGHT${NC}"
            fi
            ;;
        4) 
            read -p "Enter your Moniker (Name): " moniker
            PUBKEY=$(republicd comet show-validator)
            cat <<EOF > validator.json
{
  "pubkey": $PUBKEY,
  "amount": "1000000000000000000arai",
  "moniker": "$moniker",
  "commission-rate": "0.10",
  "commission-max-rate": "0.20",
  "commission-max-change-rate": "0.01",
  "min-self-delegation": "1"
}
EOF
            republicd tx staking create-validator validator.json --from wallet --chain-id raitestnet_77701-1 --gas auto --gas-adjustment 1.5 --yes
            ;;
        5) 
            republicd query staking validator $(republicd keys show wallet --bech val -a)
            ;;
        6) 
            republicd query bank balances $(republicd keys show wallet -a)
            ;;
        7) exit 0 ;;
        *) echo -e "${RED}Invalid option!${NC}" ;;
    esac
done
