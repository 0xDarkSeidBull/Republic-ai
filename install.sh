#!/bin/bash

# --- COLORS ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' 

# --- HEADER ---
clear
echo -e "${BLUE}=================================================${NC}"
echo -e "${GREEN}    REPUBLIC PROTOCOL MASTER INSTALLER v0.3.0    ${NC}"
echo -e "${BLUE}=================================================${NC}"

# --- MENU FUNCTION ---
show_menu() {
    echo -e "\n${YELLOW}--- MAIN MENU ---${NC}"
    echo -e "1) 🚀 Install Node (Step 0 to Sync)"
    echo -e "2) 🔑 Create New Wallet (Mnemonic Info)"
    echo -e "3) 📊 Check Sync Status (Catching Up?)"
    echo -e "4) 🛡️ Create Validator (Only if Synced)"
    echo -e "5) 🔍 Check Validator Status"
    echo -e "6) 💰 Check Wallet Balance"
    echo -e "7) ❌ Exit"
    echo -e "${BLUE}=================================================${NC}"
}

# --- 1. INSTALLATION LOGIC ---
install_node() {
    echo -e "${YELLOW}Cleaning old installation...${NC}"
    sudo systemctl stop republicd 2>/dev/null || true
    pkill republicd 2>/dev/null || true
    rm -rf $HOME/.republic
    sudo rm -f /usr/local/bin/republicd

    echo -e "${YELLOW}Installing Dependencies...${NC}"
    sudo apt update && sudo apt install curl jq lz4 build-essential -y
    
    echo -e "${YELLOW}Installing Go 1.22.5...${NC}"
    cd $HOME
    wget -q "https://go.dev/dl/go1.22.5.linux-amd64.tar.gz"
    sudo rm -rf /usr/local/go && sudo tar -C /usr/local -xzf go1.22.5.linux-amd64.tar.gz
    export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin
    grep -qxF 'export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin' $HOME/.bash_profile || echo 'export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin' >> $HOME/.bash_profile
    source $HOME/.bash_profile

    echo -e "${YELLOW}Downloading Republic Binary v0.3.0...${NC}"
    wget -q https://github.com/RepublicAI/networks/releases/download/v0.3.0/republicd-linux-amd64 -O republicd
    chmod +x republicd && sudo mv republicd /usr/local/bin/republicd

    echo -e "${YELLOW}Initializing Node...${NC}"
    republicd init "RepublicNode" --chain-id raitestnet_77701-1
    curl -L https://raw.githubusercontent.com/RepublicAI/networks/main/testnet/genesis.json -o $HOME/.republic/config/genesis.json
    
    # Auto-Peer Detection
    echo -e "${YELLOW}Fetching latest peers...${NC}"
    PEERS=$(curl -sS https://rpc-t.republic.vinjan-inc.com/net_info | jq -r '.result.peers[] | "\(.node_info.id)@\(.remote_ip):\(.node_info.listen_addr)"' | awk -F ':' '{print $1":"$(NF)}' | paste -sd "," -)
    sed -i "s/^persistent_peers *=.*/persistent_peers = \"$PEERS\"/" $HOME/.republic/config/config.toml
    sed -i 's/^indexer *=.*/indexer = "null"/' $HOME/.republic/config/config.toml

    # Fast Sync via Snapshot
    echo -e "${YELLOW}Downloading Snapshot for Fast Sync...${NC}"
    curl -L https://snapshot.vinjan-inc.com/republic/latest.tar.lz4 | lz4 -dc - | tar -xf - -C $HOME/.republic

    echo -e "${YELLOW}Starting Systemd Service...${NC}"
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
    echo -e "${GREEN}✅ INSTALLATION COMPLETE! Node is syncing in background.${NC}"
}

# --- LOOP MENU ---
while true; do
    show_menu
    # CRITICAL FIX: read from /dev/tty to prevent infinite loops in piped scripts
    read -p "Selection: " opt < /dev/tty
    
    case $opt in
        1) install_node ;;
        2) 
            echo -e "${YELLOW}Generating Wallet... PLEASE BACKUP THE MNEMONIC!${NC}"
            republicd keys add wallet
            ;;
        3) 
            SYNC_STATUS=$(republicd status 2>/dev/null | jq -r '.sync_info.catching_up')
            CUR_HEIGHT=$(republicd status 2>/dev/null | jq -r '.sync_info.latest_block_height')
            if [ "$SYNC_STATUS" == "false" ]; then
                echo -e "${GREEN}✅ NODE FULLY SYNCED! Height: $CUR_HEIGHT${NC}"
            else
                echo -e "${RED}⏳ STILL SYNCING... Current Height: $CUR_HEIGHT (Catching up: $SYNC_STATUS)${NC}"
            fi
            ;;
        4) 
            read -p "Enter your Validator Name (Moniker): " moniker < /dev/tty
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
            echo -e "${YELLOW}Sending Create-Validator Transaction...${NC}"
            republicd tx staking create-validator validator.json --from wallet --chain-id raitestnet_77701-1 --gas auto --gas-adjustment 1.5 --yes
            ;;
        5) 
            ADDR=$(republicd keys show wallet --bech val -a 2>/dev/null)
            if [ -z "$ADDR" ]; then echo "No wallet found."; else republicd query staking validator $ADDR; fi
            ;;
        6) 
            W_ADDR=$(republicd keys show wallet -a 2>/dev/null)
            if [ -z "$W_ADDR" ]; then echo "No wallet found."; else republicd query bank balances $W_ADDR; fi
            ;;
        7) 
            echo -e "${BLUE}Exiting... Happy Staking!${NC}"
            exit 0 
            ;;
        *) 
            echo -e "${RED}Invalid option! Try again.${NC}"
            sleep 1
            ;;
    esac
done
