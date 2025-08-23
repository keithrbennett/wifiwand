#!/bin/bash

# Demo script for wifi-wand that anonymizes sensitive data while running real commands
# Usage: ./demo-wifi-wand.sh [wifi-wand-command] [args...]
# Example: ./demo-wifi-wand.sh info -o json

# Anonymized demo data
DEMO_NETWORK="CafeBleu_5G"
DEMO_IP="192.168.1.105"
DEMO_MAC="aa:bb:cc:dd:ee:ff"
DEMO_ROUTER="192.168.1.1"
DEMO_INTERFACE="wlp0s20f3"

# Demo networks list
DEMO_NETWORKS='["CafeBleu_5G", "CoffeeShop_Guest", "HomeNetwork_2.4G", "LibraryWiFi", "xfinitywifi"]'

# Demo preferred networks
DEMO_PREFERRED='["CafeBleu_5G", "HomeNetwork_5G", "OfficeWiFi", "LibraryWiFi", "Hotel_Guest"]'

# Demo nameservers
DEMO_NAMESERVERS='["192.168.1.1", "8.8.8.8"]'

# Function to create demo info hash based on output format
create_demo_info() {
    local format="$1"
    case "$format" in
        "json"|"j")
            echo '{"network":"'$DEMO_NETWORK'","interface":"'$DEMO_INTERFACE'","ip_address":"'$DEMO_IP'","mac_address":"'$DEMO_MAC'","router":"'$DEMO_ROUTER'","nameservers":["192.168.1.1","8.8.8.8"]}'
            ;;
        "yaml"|"y")
            cat << EOF
---
network: $DEMO_NETWORK
interface: $DEMO_INTERFACE
ip_address: $DEMO_IP
mac_address: $DEMO_MAC
router: $DEMO_ROUTER
nameservers:
- 192.168.1.1
- 8.8.8.8
EOF
            ;;
        *)
            # Default pretty format (similar to awesome_print)
            cat << 'EOF'
{
          "network" => "CafeBleu_5G",
        "interface" => "wlp0s20f3",
      "ip_address" => "192.168.1.105",
     "mac_address" => "aa:bb:cc:dd:ee:ff",
          "router" => "192.168.1.1",
    "nameservers" => ["192.168.1.1", "8.8.8.8"]
}
EOF
            ;;
    esac
}

# Function to format array output based on format
format_array_output() {
    local data="$1"
    local format="$2"
    case "$format" in
        "json"|"j")
            echo "$data"
            ;;
        "yaml"|"y")
            echo "$data" | jq -r 'to_entries[] | "- " + .value'
            ;;
        *)
            # Default array format (similar to awesome_print)
            echo "$data" | jq -r 'to_entries[] | "    [\(.key)] \"\(.value)\","' | sed '$s/,$//'
            echo "$data" | jq -r 'to_entries | "[\n" + (map("    [\(.key)] \"\(.value)\"") | join(",\n")) + "\n]"' > /dev/null 2>&1
            # Simpler approach:
            cat << EOF
[
$(echo "$data" | jq -r 'to_entries[] | "    [\(.key)] \"\(.value)\","' | sed '$s/,$//')
]
EOF
            ;;
    esac
}

# Parse output format from arguments
OUTPUT_FORMAT=""
if [[ " $* " =~ " -o " ]]; then
    # Find the argument after -o
    args=("$@")
    for i in "${!args[@]}"; do
        if [[ "${args[$i]}" == "-o" ]] && [[ $((i+1)) -lt ${#args[@]} ]]; then
            OUTPUT_FORMAT="${args[$((i+1))]}"
            break
        fi
    done
fi

# Main command handling
case "$1" in
    # Commands that return sensitive info - use demo data
    "info"|"i")
        create_demo_info "$OUTPUT_FORMAT"
        ;;
    
    "avail_nets"|"available_networks"|"a")
        format_array_output "$DEMO_NETWORKS" "$OUTPUT_FORMAT"
        ;;
    
    "pref_nets"|"preferred_networks"|"pr")
        format_array_output "$DEMO_PREFERRED" "$OUTPUT_FORMAT"
        ;;
    
    "network_name"|"ne")
        echo "$DEMO_NETWORK"
        ;;
        
    "nameservers"|"na")
        if [[ "$2" == ":clear" ]] || [[ "$2" == "clear" ]]; then
            echo "[]"
        elif [[ -n "$2" ]]; then
            # Setting nameservers - echo back the arguments as array
            shift
            printf "["
            printf '"%s",' "$@" | sed 's/,$//'
            printf "]\n"
        else
            # Show current nameservers
            format_array_output "$DEMO_NAMESERVERS" "$OUTPUT_FORMAT"
        fi
        ;;
    
    "password"|"pa")
        if [[ -n "$2" ]]; then
            # Return a demo password based on network name
            case "$2" in
                *"Home"*|*"home"*)
                    echo "my_home_password"
                    ;;
                *"Office"*|*"office"*)
                    echo "office_wifi_123"
                    ;;
                *"Cafe"*|*"cafe"*|*"Coffee"*)
                    echo "my_cafe_password_123"
                    ;;
                *)
                    echo "demo_password_456"
                    ;;
            esac
        else
            echo "Error: network name required"
            exit 1
        fi
        ;;
    
    "forget"|"f")
        # Simulate forgetting networks - echo back what was "removed"
        shift
        printf "["
        printf '"%s",' "$@" | sed 's/,$//'
        printf "]\n"
        ;;
    
    # Commands that are safe to run for real
    "wifi_on"|"w"|"connected_to_internet"|"ci"|"on"|"off"|"cycle"|"disconnect"|"quit"|"exit"|"help"|"h")
        cd "$(dirname "$0")/.." && bundle exec exe/wifi-wand "$@"
        ;;
    
    # Till command - simulate with demo output
    "till"|"t")
        if [[ "$2" == ":conn" ]]; then
            # Simulate waiting with block output if provided
            if [[ "$*" == *"Time.now"* ]]; then
                echo "$(date '+%Y-%m-%d %H:%M:%S %z'): Waiting for connection..."
                sleep 0.5
                echo "$(date '+%Y-%m-%d %H:%M:%S %z'): Waiting for connection..."
                sleep 0.5
                echo "true"
            else
                sleep 1
                echo "true"
            fi
        else
            cd "$(dirname "$0")/.." && bundle exec exe/wifi-wand "$@"
        fi
        ;;
    
    # Shell mode - pass through to real command (user can use demo commands inside)
    "-s"|"--shell")
        echo "Note: In shell mode, you can use this demo script by prefixing commands with:"
        echo "      .$(realpath "$0") [command]"
        echo "Starting real wifi-wand shell..."
        cd "$(dirname "$0")/.." && bundle exec exe/wifi-wand "$@"
        ;;
    
    # Default - pass through to real wifi-wand
    *)
        cd "$(dirname "$0")/.." && bundle exec exe/wifi-wand "$@"
        ;;
esac