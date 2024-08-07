#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

# Function to check if script is run as root
check_root() {
    if [ "$(id -u)" != "0" ]; then
        echo "This script must be run as root" 1>&2
        exit 1
    fi
}

# Function to install dependencies
install_dependencies() {
    apt-get update
    apt-get install -y iptables
}

# Function to create VNC protection script
create_vnc_protection_script() {
    cat > /usr/local/bin/firewall-vnc << EOL
#!/bin/bash

# Configuration
VNC_PORT=9901  # VNC port to protect
MAX_ATTEMPTS=1
LOG_FILE="/var/log/vnc-protection.log"
WHITELIST_FILE="/etc/vnc-protection-whitelist"
BLACKLIST_FILE="/etc/vnc-protection-blacklist"

# Function to add IP to blacklist (ban for VNC)
add_to_blacklist() {
    local ip=\$1
    if ! grep -q "^\$ip\$" "\$BLACKLIST_FILE"; then
        echo "\$ip" >> "\$BLACKLIST_FILE"
        iptables -I INPUT 1 -s \$ip -p tcp --dport \$VNC_PORT -j DROP
        echo "\$(date): Blocked \$ip for VNC access" >> "\$LOG_FILE"
        echo "IP \$ip has been banned for VNC access."
    else
        echo "IP \$ip is already in the blacklist."
    fi
}

# Function to remove IP from blacklist
remove_from_blacklist() {
    local ip=\$1
    if grep -q "^\$ip\$" "\$BLACKLIST_FILE"; then
        sed -i "/^\$ip\$/d" "\$BLACKLIST_FILE"
        iptables -D INPUT -s \$ip -p tcp --dport \$VNC_PORT -j DROP
        echo "\$(date): Unbanned \$ip for VNC access" >> "\$LOG_FILE"
        echo "IP \$ip has been removed from the blacklist."
    else
        echo "IP \$ip is not in the blacklist."
    fi
}

# Function to add IP to whitelist
add_to_whitelist() {
    local ip=\$1
    if ! grep -q "^\$ip\$" "\$WHITELIST_FILE"; then
        echo "\$ip" >> "\$WHITELIST_FILE"
        iptables -I INPUT 1 -s \$ip -p tcp --dport \$VNC_PORT -j ACCEPT
        echo "\$(date): Whitelisted \$ip for VNC access" >> "\$LOG_FILE"
        echo "IP \$ip has been added to the whitelist for VNC access."
    else
        echo "IP \$ip is already in the whitelist."
    fi
}

# Function to remove IP from whitelist
remove_from_whitelist() {
    local ip=\$1
    if grep -q "^\$ip\$" "\$WHITELIST_FILE"; then
        sed -i "/^\$ip\$/d" "\$WHITELIST_FILE"
        iptables -D INPUT -s \$ip -p tcp --dport \$VNC_PORT -j ACCEPT
        echo "\$(date): Removed \$ip from whitelist for VNC access" >> "\$LOG_FILE"
        echo "IP \$ip has been removed from the whitelist."
    else
        echo "IP \$ip is not in the whitelist."
    fi
}

# Function to show all lists
show_lists() {
    echo "Whitelist (Allowed VNC access):"
    cat "\$WHITELIST_FILE"
    echo ""
    echo "Blacklist (Banned from VNC access):"
    cat "\$BLACKLIST_FILE"
}

# Function to check current iptables rules for VNC
check_iptables_rules() {
    echo "Current iptables rules for VNC (port \$VNC_PORT):"
    iptables -L INPUT -n -v | grep \$VNC_PORT
}

# Function to start monitoring
start_monitoring() {
    while true; do
        tail -f /home/desktop/.vnc/ubuntu:1.log | while read line; do
            if echo \$line | grep -q "authentication failed"; then
                ip=\$(echo \$line | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b")
                if ! grep -q "^\$ip\$" "\$WHITELIST_FILE"; then
                    count=\$(grep \$ip \$LOG_FILE | wc -l)
                    
                    if [ \$count -ge \$MAX_ATTEMPTS ]; then
                        add_to_blacklist \$ip
                    else
                        echo "\$(date): Failed attempt from \$ip (Attempt \$((count+1)))" >> \$LOG_FILE
                        echo "\$(date): Failed attempt from \$ip (Attempt \$((count+1)))"
                    fi
                fi
            fi
        done
    done
}

# Function to apply existing blacklist and whitelist rules
apply_existing_rules() {
    echo "Applying existing whitelist and blacklist rules for VNC..."
    
    # Apply whitelist rules
    while IFS= read -r ip; do
        iptables -I INPUT 1 -s \$ip -p tcp --dport \$VNC_PORT -j ACCEPT
    done < "\$WHITELIST_FILE"

    # Apply blacklist rules
    while IFS= read -r ip; do
        iptables -I INPUT 1 -s \$ip -p tcp --dport \$VNC_PORT -j DROP
    done < "\$BLACKLIST_FILE"

    echo "VNC protection rules applied."
    check_iptables_rules
}

# Main script
case "\$1" in
    --whitelist)
        add_to_whitelist "\$2"
        check_iptables_rules
        ;;
    --unwhitelist)
        remove_from_whitelist "\$2"
        check_iptables_rules
        ;;
    --blacklist)
        add_to_blacklist "\$2"
        check_iptables_rules
        ;;
    --unblacklist)
        remove_from_blacklist "\$2"
        check_iptables_rules
        ;;
    --show)
        show_lists
        check_iptables_rules
        ;;
    --monitor)
        start_monitoring
        ;;
    --apply-rules)
        apply_existing_rules
        ;;
    --check-rules)
        check_iptables_rules
        ;;
    *)
        echo "Usage: \$0 {--whitelist|--unwhitelist|--blacklist|--unblacklist} IP"
        echo "       \$0 --show"
        echo "       \$0 --monitor"
        echo "       \$0 --apply-rules"
        echo "       \$0 --check-rules"
        exit 1
        ;;
esac

exit 0
EOL

    chmod +x /usr/local/bin/firewall-vnc
}

# Function to create systemd service file
create_systemd_service() {
    cat > /etc/systemd/system/vnc-protection.service << EOL
[Unit]
Description=VNC Protection Service
After=network.target

[Service]
ExecStart=/usr/local/bin/firewall-vnc --monitor
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOL
}

# Function to setup and start the service
setup_and_start_service() {
    systemctl daemon-reload
    systemctl enable vnc-protection.service
    systemctl start vnc-protection.service
}

# Main installation process
main() {
    check_root
    install_dependencies
    create_vnc_protection_script
    create_systemd_service
    touch /etc/vnc-protection-whitelist /etc/vnc-protection-blacklist
    setup_and_start_service
    
    echo "VNC Protection has been installed and started."
    echo "You can manage it using: systemctl {start|stop|restart|status} vnc-protection.service"
    echo "To whitelist an IP: /usr/local/bin/firewall-vnc --whitelist IP"
    echo "To blacklist an IP: /usr/local/bin/firewall-vnc --blacklist IP"
    echo "To check current rules: /usr/local/bin/firewall-vnc --check-rules"
}

# Run the main function
main

exit 0
