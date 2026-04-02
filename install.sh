#!/bin/bash

# --- COLORS ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' 

# --- FUNCTION: REFRESH PEERS (The Healer) ---
refresh_peers() {
    echo -e "${YELLOW}🔍 Clearing old peer cache and searching for LIVE peers...${NC}"
    sudo systemctl stop republicd 2>/dev/null
    
    # Ye step sabse zaruri hai: Bucket full error ko khatam karne ke liye
    rm -f $HOME/.republic/config/addrbook.json
    
    # Live peers fetch from RPC
    NEW_PEERS=$(curl -sS https://rpc-t.republic.vinjan-inc.com/net_info | jq -r '.result.peers[] | "\(.node_info.id)@\(.remote_ip):\(.node_info.listen_addr)"' | awk -F ':' '{print $1":"$(NF)}' | paste -sd "," -)
    
    if [ -z "$NEW_PEERS" ]; then
        echo -e "${RED}❌ RPC Unreachable! Using Static Backup Peers...${NC}"
        NEW_PEERS="49033331b269403a4c004a4bc3b63297a7a53609@195.201.160.23:26656,6649171f163836371f654b6932402127f8a7e0d3@144.76.202.124:26656,870d06990d0b77139194270d496078345c61303e@65.108.248.79:26656"
    fi
    
    sed -i "s/^persistent_peers *=.*/persistent_peers = \"$NEW_PEERS\"/" $HOME/.republic/config/config.toml
    sudo systemctl start republicd
    echo -e "${GREEN}✅ Config Updated! Node Restarted.${NC}"
}

# --- MENU ---
show_menu() {
    clear
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${GREEN}    REPUBLIC PROTOCOL MASTER INSTALLER v0.3.5    ${NC}"
    echo -e "${BLUE}=================================================${NC}"
    echo -e "1) 🚀 Install Node (Step 0 to Start)"
    echo -e "2) 🔑 Create New Wallet (Backup Mnemonic)"
    echo -e "3) 📊 Check Sync Status (Auto-Fix if Stuck)"
    echo -e "4) 🛡️ Create Validator (Synced Users Only)"
    echo -e "5) 🔍 Check Validator Status"
    echo -e "6) 💰 Check Wallet Balance"
    echo -e "7) 🔄 Manual Peer Refresh (Fix Timeouts)"
    echo -e "8) ❌ Exit"
    echo -e "${BLUE}=================================================${NC}"
}

# --- INSTALLATION ---
install_node() {
    echo -e "${YELLOW}Cleaning previous installation...${NC}"
    sudo systemctl stop republicd 2>/dev/null || true
    rm -rf $HOME/.republic
    sudo rm -f /usr/local/bin/republicd

    echo -e "${YELLOW}Installing Deps & Go...${NC}"
    sudo apt update && sudo apt install curl jq lz4 build-essential -y
    wget -q "https://go.dev/dl/go1.22.5.linux-amd64.tar.gz"
    sudo rm -rf /usr/local/go && sudo tar -C /usr/local -xzf go1.22.5.linux-amd64.tar.gz
    export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin
    echo 'export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin' >> $HOME/.bash_profile
    source $HOME/.bash_profile

    echo -e "${YELLOW}Downloading Binary v0.3.0...${NC}"
    wget -q https://github.com/RepublicAI/networks/releases/download/v0.3.0/republicd-linux-amd64 -O republicd
    chmod +x republicd && sudo mv republicd /usr/local/bin/republicd

    republicd init "RepublicNode" --chain-id raitestnet_77701-1
    curl -L https://raw.githubusercontent.com/RepublicAI/networks/main/testnet/genesis.json -o $HOME/.republic/config/genesis.json
    
    # Fast Sync via Snapshot
    echo -e "${YELLOW}Applying Snapshot...${NC}"
    curl -L https://snapshot.vinjan-inc.com/republic/latest.tar.lz4 | lz4 -dc - | tar -xf - -C $HOME/.republic

    # Set Initial Peers
    refresh_peers

    # Service Creation
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
    echo -e "${GREEN}✅ Installation Finished! Node is running.${NC}"
    read -p "Press Enter to return to menu..." < /dev/tty
}

# --- MAIN LOOP ---
while true; do
    show_menu
    read -p "Selection [1-8]: " opt < /dev/tty
    
    case $opt in
        1) install_node ;;
        2) 
            republicd keys add wallet
            echo -e "${RED}SAVE THE ABOVE MNEMONIC NOW!${NC}"
            read -p "Done? Press Enter..." < /dev/tty
            ;;
        3) 
            STATUS=$(republicd status 2>/dev/null | jq -r '.sync_info.catching_up')
            HEIGHT=$(republicd status 2>/dev/null | jq -r '.sync_info.latest_block_height')
            if [ "$STATUS" == "false" ] && [ "$HEIGHT" != "0" ]; then
                echo -e "${GREEN}✅ SYNCED! Current Height: $HEIGHT${NC}"
            else
                echo -e "${RED}⏳ SYNCING... Height: $HEIGHT (Catching up: $STATUS)${NC}"
                echo -e "If height is stuck, use Option 7 to refresh peers."
            fi
            read -p "Press Enter..." < /dev/tty
            ;;
        4) 
            read -p "Enter Moniker: " mon < /dev/tty
            PUB=$(republicd comet show-validator)
            cat <<EOF > validator.json
{
  "pubkey": $PUB,
  "amount": "1000000000000000000arai",
  "moniker": "$mon",
  "commission-rate": "0.10",
  "commission-max-rate": "0.20",
  "commission-max-change-rate": "0.01",
  "min-self-delegation": "1"
}
EOF
            republicd tx staking create-validator validator.json --from wallet --chain-id raitestnet_77701-1 --gas auto --gas-adjustment 1.5 --yes
            read -p "Press Enter..." < /dev/tty
            ;;
        5) 
            ADDR=$(republicd keys show wallet --bech val -a 2>/dev/null)
            republicd query staking validator $ADDR
            read -p "Press Enter..." < /dev/tty
            ;;
        6) 
            W_ADDR=$(republicd keys show wallet -a 2>/dev/null)
            republicd query bank balances $W_ADDR
            read -p "Press Enter..." < /dev/tty
            ;;
        7) 
            refresh_peers 
            read -p "Peers Refreshed. Press Enter..." < /dev/tty
            ;;
        8) exit 0 ;;
        *) echo "Invalid Option"; sleep 1 ;;
    esac
done
