#!/bin/bash

echo "🔄 Post Scratch Org Setup: Starting..."

# Define the Scratch Org Alias
SCRATCH_ORG_ALIAS="MyScratchOrg"

# Check if the Scratch Org exists
echo "✅ Checking Scratch Org status..."
sfdx force:org:list | grep -q "$SCRATCH_ORG_ALIAS"
if [ $? -ne 0 ]; then
    echo "❌ Scratch Org '$SCRATCH_ORG_ALIAS' not found. Exiting."
    exit 1
fi

# Push source metadata (deploy custom objects, fields, etc.)
echo "🚀 Pushing metadata to Scratch Org..."
sfdx force:source:push -u "$SCRATCH_ORG_ALIAS"

# Load Custom Data (CSV example for Accounts)
echo "📂 Loading custom Account data..."
sfdx force:data:bulk:upsert -s Account -f data/accounts.csv -i Name -u "$SCRATCH_ORG_ALIAS"

# Open Scratch Org (optional)
echo "🌐 Opening Scratch Org..."
sfdx force:org:open -u "$SCRATCH_ORG_ALIAS"

echo "✅ Post Scratch Org Setup: Completed!"
