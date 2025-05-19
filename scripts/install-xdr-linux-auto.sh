#!/bin/bash

# --- Check prerequisites ---
# Check for required arguments
if [ $# -lt 4 ]; then
    echo "Error: Missing arguments."
    echo "Usage: $0 <XDR_URL> <DISTRIBUTION_ID> <AUTH_ID> <AUTH_TOKEN> [XDR_TAGS]"
    exit 1
fi

# --- jq Installation Check ---
# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo "Warning: The 'jq' package is not installed."
    echo "jq is required to process JSON API responses. Attempting automatic installation..."

    # Detect the distribution to use the correct package manager
    PACKAGE_MANAGER=""
    if [ -f /etc/os-release ]; then
        # Source the file to use the variables like ID, VERSION_ID, etc.
        . /etc/os-release
        DISTRO_ID=$ID
        DISTRO_LIKE=$ID_LIKE # Some distros set ID_LIKE

        case "$DISTRO_ID" in
            debian|ubuntu)
                PACKAGE_MANAGER="apt"
                ;;
            centos|rhel|fedora|almalinux|rocky)
                # Check for dnf first (newer Fedora/RHEL)
                if command -v dnf &> /dev/null; then
                     PACKAGE_MANAGER="dnf"
                else
                     PACKAGE_MANAGER="yum"
                fi
                ;;
            *)
                # Fallback for ID_LIKE if main ID is not matched
                case "$DISTRO_LIKE" in
                    debian)
                        PACKAGE_MANAGER="apt"
                        ;;
                    rhel)
                         if command -v dnf &> /dev/null; then
                             PACKAGE_MANAGER="dnf"
                         else
                             PACKAGE_MANAGER="yum"
                         fi
                        ;;
                    *)
                        echo "Error: Unhandled distribution for automatic jq installation."
                        echo "Please install jq manually and rerun the script."
                        exit 1
                        ;;
                esac
                ;;
        esac
    else
        # Fallback for older systems if /etc/os-release doesn't exist
        if command -v apt-get &> /dev/null; then
            PACKAGE_MANAGER="apt"
        elif command -v yum &> /dev/null; then
            PACKAGE_MANAGER="yum"
        elif command -v dnf &> /dev/null; then
             PACKAGE_MANAGER="dnf"
        else
            echo "Error: Unable to detect package manager. Please install jq manually."
            exit 1
        fi
    fi

    if [ -n "$PACKAGE_MANAGER" ]; then
        echo "Using $PACKAGE_MANAGER to install jq..."
        INSTALL_CMD=""
        case "$PACKAGE_MANAGER" in
            apt)
                INSTALL_CMD="sudo apt-get update && sudo apt-get install -y jq"
                ;;
            yum|dnf)
                INSTALL_CMD="sudo $PACKAGE_MANAGER install -y jq"
                ;;
        esac

        if [ -n "$INSTALL_CMD" ]; then
            echo "Executing command: $INSTALL_CMD"
            # Attempt installation
            if eval "$INSTALL_CMD"; then
                echo "'jq' was installed successfully."
            else
                echo "Error: Failed to install 'jq' automatically."
                echo "Please check permissions (sudo access) or install jq manually."
                exit 1
            fi
        fi
    fi

    # Re-check if jq is now installed after automatic attempt
    if ! command -v jq &> /dev/null; then
        echo "Error: 'jq' is still not found after the automatic installation attempt."
        echo "Please install jq manually and rerun the script."
        exit 1
    fi
else
    echo "'jq' is already installed. Proceeding with the script."
fi
# --- End of jq check ---
# --- End of checks ---


# Assign arguments to variables
XDR_URL=$1
DISTRIBUTION_ID=$2
AUTH_ID=$3
AUTH_TOKEN=$4
XDR_TAGS=$5 # May be empty if not provided

# Health Check API
HEALTHCHECK_URL="$XDR_URL/public_api/v1/healthcheck"

# Perform health check
health_response=$(curl --silent --location "$HEALTHCHECK_URL" \
--header "Accept: application/json" \
--header "x-xdr-auth-id: $AUTH_ID" \
--header "Authorization: $AUTH_TOKEN")

# Extract the status from the health response
health_status=$(echo "$health_response" | jq -r '.status')

# Check if the API is available
if [[ "$health_status" != "available" ]]; then
    echo "API health check failed. Status: $health_status"
    exit 1
fi

echo "API is healthy. Proceeding with the distribution URL request..."

# Variables for the distribution URL request
API_URL="$XDR_URL/public_api/v1/distributions/get_dist_url"
PACKAGE_TYPE="sh"

# Make the request using curl and capture the output
response=$(curl --silent --location "$API_URL" \
--header "Accept: application/json" \
--header "x-xdr-auth-id: $AUTH_ID" \
--header "Authorization: $AUTH_TOKEN" \
--header "Content-Type: application/json" \
--data '{
    "request_data": {
        "distribution_id": "'$DISTRIBUTION_ID'",
        "package_type": "'$PACKAGE_TYPE'"
    }
}')

# Extract the distribution_url from the response
distribution_url=$(echo "$response" | jq -r '.reply.distribution_url')

# Check if distribution_url was extracted
if [[ -z "$distribution_url" || "$distribution_url" == "null" ]]; then
    echo "Failed to retrieve distribution_url from the response."
    exit 1
fi

echo "Distribution URL: $distribution_url"

# Use the extracted distribution_url in the next curl command and save the output to XDR-Linux.tar.gz
curl --silent --location --request POST "$distribution_url" \
--header 'Accept: application/json' \
--header "x-xdr-auth-id: $AUTH_ID" \
--header "Authorization: $AUTH_TOKEN" \
--output /tmp/XDR-Linux.tar.gz

echo "The output has been saved to /tmp/XDR-Linux.tar.gz"

# Install Cortex xDR Agent Installation

cd /tmp
mkdir -p xdr # Use -p to avoid error if directory already exists
mv XDR-Linux.tar.gz xdr
cd xdr
tar -zxvf XDR-Linux.tar.gz
sudo mkdir -p /etc/panw
sudo cp cortex.conf /etc/panw/
sudo chmod +x *.sh
sudo bash cortex-*.sh -- --endpoint-tags $XDR_TAGS
