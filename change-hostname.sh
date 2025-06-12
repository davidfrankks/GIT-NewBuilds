#!/bin/bash

# Script to change hostname and MAC address for cloned Linux VMs
# Usage: sudo ./change_vm_identity.sh -h new_hostname [-m xx:xx:xx:xx:xx:xx]

# Default values
NEW_HOSTNAME=""
NEW_MAC=""
GENERATE_MAC=true

# Function to generate a random MAC address
generate_random_mac() {
    # Generate a random MAC address with the locally administered bit set
    # (The second character is 2, 6, A, or E)
    printf "52:%02x:%02x:%02x:%02x:%02x" $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256))
}

# Function to validate MAC address format
validate_mac() {
    local mac=$1
    if [[ ! $mac =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]]; then
        echo "Invalid MAC address format. Please use format xx:xx:xx:xx:xx:xx"
        exit 1
    fi
}

# Parse command line arguments
while getopts "h:m:" opt; do
    case $opt in
        h)
            NEW_HOSTNAME=$OPTARG
            ;;
        m)
            NEW_MAC=$OPTARG
            GENERATE_MAC=false
            validate_mac "$NEW_MAC"
            ;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
            echo "Usage: sudo $0 -h new_hostname [-m xx:xx:xx:xx:xx:xx]" >&2
            exit 1
            ;;
        :)
            echo "Option -$OPTARG requires an argument." >&2
            echo "Usage: sudo $0 -h new_hostname [-m xx:xx:xx:xx:xx:xx]" >&2
            exit 1
            ;;
    esac
done

# Check if script is running as root
if [ "$EUID" -ne 0 ]; then
    echo "This script must be run as root (use sudo)"
    exit 1
fi

# Check if hostname is provided
if [ -z "$NEW_HOSTNAME" ]; then
    echo "No hostname provided. Please specify a hostname with -h option."
    echo "Usage: sudo $0 -h new_hostname [-m xx:xx:xx:xx:xx:xx]"
    exit 1
fi

# Generate a random MAC if not provided
if [ "$GENERATE_MAC" = true ]; then
    NEW_MAC=$(generate_random_mac)
    echo "Generated random MAC address: $NEW_MAC"
fi

# Get the old hostname
OLD_HOSTNAME=$(hostname)
echo "Old hostname: $OLD_HOSTNAME"
echo "New hostname: $NEW_HOSTNAME"

# Get a list of network interfaces (excluding lo)
INTERFACES=$(ip -o link show | grep -v "lo:" | awk -F': ' '{print $2}')

# Function to detect the Linux distribution
detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo "$ID"
    elif [ -f /etc/redhat-release ]; then
        echo "rhel"
    elif [ -f /etc/debian_version ]; then
        echo "debian"
    else
        echo "unknown"
    fi
}

DISTRO=$(detect_distro)
echo "Detected Linux distribution: $DISTRO"

# Change hostname
echo "Changing hostname from $OLD_HOSTNAME to $NEW_HOSTNAME..."

# Update hostname in different files based on distro
hostnamectl set-hostname "$NEW_HOSTNAME" 2>/dev/null || {
    # Fall back if hostnamectl doesn't work
    echo "$NEW_HOSTNAME" > /etc/hostname
}

# Update /etc/hosts file
sed -i "s/\b$OLD_HOSTNAME\b/$NEW_HOSTNAME/g" /etc/hosts

# Update network configuration files for the MAC address
echo "Detected network interfaces: $INTERFACES"
for interface in $INTERFACES; do
    # Skip virtual interfaces
    if [[ "$interface" == "veth"* || "$interface" == "docker"* ]]; then
        continue
    fi

    echo "Updating interface $interface with new MAC: $NEW_MAC"

    # Bring down the interface
    ip link set "$interface" down

    # Set new MAC address
    ip link set "$interface" address "$NEW_MAC"

    # Update configuration files based on distro
    case "$DISTRO" in
        "ubuntu"|"debian")
            # Check for Netplan
            if [ -d /etc/netplan ]; then
                echo "Updating Netplan configuration..."
                for netplan_file in /etc/netplan/*.yaml; do
                    if [ -f "$netplan_file" ]; then
                        # Backup the file
                        cp "$netplan_file" "$netplan_file.bak"

                        # Update MAC address
                        sed -i "/macaddress:/c\      macaddress: $NEW_MAC" "$netplan_file"

                        # If no macaddress line exists, add it under the interface
                        if ! grep -q "macaddress:" "$netplan_file"; then
                            sed -i "/\b$interface\b/a\      macaddress: $NEW_MAC" "$netplan_file"
                        fi
                    fi
                done
                netplan apply 2>/dev/null || echo "Note: Please reboot to apply Netplan changes"
            fi

            # Check for legacy network configuration
            if [ -f /etc/network/interfaces ]; then
                echo "Updating /etc/network/interfaces..."
                cp /etc/network/interfaces /etc/network/interfaces.bak
                sed -i "/hwaddress.*$interface/c\iface $interface inet dhcp\n    hwaddress ether $NEW_MAC" /etc/network/interfaces
            fi
            ;;

        "centos"|"rhel"|"fedora"|"rocky"|"almalinux")
            # For RHEL-based distros
            if [ -d /etc/sysconfig/network-scripts ]; then
                echo "Updating network scripts..."
                config_file="/etc/sysconfig/network-scripts/ifcfg-$interface"
                if [ -f "$config_file" ]; then
                    cp "$config_file" "$config_file.bak"
                    if grep -q "^HWADDR=" "$config_file"; then
                        sed -i "s/^HWADDR=.*/HWADDR=$NEW_MAC/" "$config_file"
                    else
                        echo "HWADDR=$NEW_MAC" >> "$config_file"
                    fi
                    if grep -q "^MACADDR=" "$config_file"; then
                        sed -i "s/^MACADDR=.*/MACADDR=$NEW_MAC/" "$config_file"
                    fi
                fi
            fi
            ;;

        *)
            echo "Unsupported distribution for automatic network configuration updates."
            echo "MAC address changed for current session, but you may need to update config files manually."
            ;;
    esac

    # Bring up the interface
    ip link set "$interface" up
done

# Check if cloud-init is installed and reset it
if command -v cloud-init >/dev/null 2>&1; then
    echo "Resetting cloud-init..."
    cloud-init clean --logs
    rm -rf /var/lib/cloud/instances/*
fi

# Clean up machine-id to ensure uniqueness
echo "Resetting machine-id..."
rm -f /etc/machine-id
rm -f /var/lib/dbus/machine-id
dbus-uuidgen --ensure=/etc/machine-id
[ -f /var/lib/dbus/machine-id ] || ln -s /etc/machine-id /var/lib/dbus/machine-id

echo "System identity updated successfully:"
echo "  - Hostname: $NEW_HOSTNAME"
echo "  - MAC Address: $NEW_MAC"
echo "  - Machine-ID: $(cat /etc/machine-id)"
echo
echo "NOTE: A reboot is recommended to ensure all changes take effect."
