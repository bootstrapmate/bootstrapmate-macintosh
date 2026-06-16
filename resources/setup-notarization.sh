#!/bin/zsh

# BootstrapMate Notarization Environment Setup - ECUAD Specific
# Sources Apple notarization credentials from Azure Key Vault
#
# **NOTE:** This is specific to Emily Carr University. For other organizations,
# set environment variables directly or create your own credential fetching script.
#
# Usage:
#   source setup-notarization.sh
#
# Generic alternative (for non-ECUAD users):
#   export NOTARIZATION_APPLE_ID="your@apple.id"
#   export NOTARIZATION_PASSWORD="xxxx-xxxx-xxxx-xxxx"
#   export NOTARIZATION_TEAM_ID="YOURTEAMID"

set -e

# Get script directory (works in both bash and zsh)
if [[ -n "$BASH_SOURCE" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
elif [[ -n "$ZSH_VERSION" ]]; then
    SCRIPT_DIR="${0:A:h}"
else
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Key Vault configuration
KEY_VAULT_NAME="munki-repo-secrets"
SUBSCRIPTION_ID="59d35012-b593-4b2f-bd50-28e666ed12f7"
TENANT_ID="d22686a0-c1be-48e0-8f91-5bdd033f7dad"

# Check Azure CLI
if ! command -v az &> /dev/null; then
    echo -e "${RED}Error: Azure CLI not installed${NC}"
    echo "Install with: brew install azure-cli"
    return 1
fi

# Check login status
if ! az account show &> /dev/null 2>&1; then
    echo -e "${YELLOW}Not logged in to Azure. Attempting login...${NC}"
    az login --tenant "$TENANT_ID" || {
        echo -e "${RED}Azure login failed${NC}"
        return 1
    }
fi

# Set subscription
az account set --subscription "$SUBSCRIPTION_ID" 2>/dev/null || true

# Fetch secrets
echo -e "${GREEN}Fetching notarization credentials from Key Vault...${NC}"

export NOTARIZATION_APPLE_ID=$(az keyvault secret show \
    --vault-name "$KEY_VAULT_NAME" \
    --name "NotarizationAppleId" \
    --query "value" -o tsv 2>/dev/null)

export NOTARIZATION_PASSWORD=$(az keyvault secret show \
    --vault-name "$KEY_VAULT_NAME" \
    --name "NotarizationPassword" \
    --query "value" -o tsv 2>/dev/null)

export NOTARIZATION_TEAM_ID="7TF6CSP83S"  # ECUAD Team ID

# ECUAD-specific signing identities
export SIGNING_IDENTITY_APP="Developer ID Application: Emily Carr University of Art and Design (7TF6CSP83S)"
export SIGNING_IDENTITY_PKG="Developer ID Installer: Emily Carr University of Art and Design (7TF6CSP83S)"
export BUNDLE_ID="ca.ecuad.macadmin.bootstrapmate"

# Verify credentials were retrieved
if [[ -z "$NOTARIZATION_APPLE_ID" ]] || [[ -z "$NOTARIZATION_PASSWORD" ]]; then
    echo -e "${RED}Error: Failed to retrieve notarization credentials${NC}"
    echo ""
    echo "Missing secrets in Key Vault:"
    [[ -z "$NOTARIZATION_APPLE_ID" ]] && echo "  - NotarizationAppleId"
    [[ -z "$NOTARIZATION_PASSWORD" ]] && echo "  - NotarizationPassword"
    echo ""
    echo "To add these secrets:"
    echo "  az keyvault secret set --vault-name ${KEY_VAULT_NAME} --name NotarizationAppleId --value 'your@apple.id'"
    echo "  az keyvault secret set --vault-name ${KEY_VAULT_NAME} --name NotarizationPassword --value 'xxxx-xxxx-xxxx-xxxx'"
    echo ""
    echo "App-specific password: https://appleid.apple.com (Security > App-Specific Passwords)"
    return 1
fi

echo -e "${GREEN}✓ Notarization credentials loaded${NC}"
echo "  Apple ID: ${NOTARIZATION_APPLE_ID}"
echo "  Team ID: ${NOTARIZATION_TEAM_ID}"
echo ""
echo -e "${YELLOW}Ready to build with notarization:${NC}"
echo "  cd ${SCRIPT_DIR}"
echo "  ./build.sh 1.0.0 \\"
echo "    --sign-app \\\"Developer ID Application: Emily Carr University (7TF6CSP83S)\\\" \\"
echo "    --sign-pkg \\\"Developer ID Installer: Emily Carr University (7TF6CSP83S)\\\""
echo ""

