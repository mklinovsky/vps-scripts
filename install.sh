#!/usr/bin/env bash

set -e

if [ ! -f ./.env ]; then
    echo "Error: .env file not found. Please create one from .env.example"
    exit 1
fi

source ./.env

echo $VPS_IP

if [ -z "$VPS_IP" ] || [ -z "$VPS_USER" ]; then
    echo "Error: VPS_IP and VPS_USER must be set in .env"
    exit 1
fi

echo "Installing scripts to $VPS_USER@$VPS_IP:/home/$VPS_USER/bin/..."

ssh "$VPS_USER@$VPS_IP" "mkdir -p /home/$VPS_USER/bin /home/$VPS_USER/log"

echo "Building mailer..."
cd mailer
GOOS=linux GOARCH=amd64 go build -o mailer .
cd ..

echo "Copying scripts..."
rsync -av scripts/ "$VPS_USER@$VPS_IP:/home/$VPS_USER/bin/"
rsync -v mailer/mailer "$VPS_USER@$VPS_IP:/home/$VPS_USER/bin/"

echo "Setting permissions..."
ssh "$VPS_USER@$VPS_IP" "chmod +x /home/$VPS_USER/bin/*"

if [ -f .env.remote ]; then
    echo "Deploying .env.remote to VPS..."
    ssh "$VPS_USER@$VPS_IP" "[ -f /home/$VPS_USER/bin/.env ] && cp /home/$VPS_USER/bin/.env /home/$VPS_USER/bin/.env.bak || true"
    rsync -v .env.remote "$VPS_USER@$VPS_IP:/home/$VPS_USER/bin/.env"
    echo "Remote .env deployed (previous version backed up as .env.bak if it existed)."
else
    echo ""
    echo "WARNING: No .env.remote found. Skipping remote .env deployment."
fi

echo ""
echo "Installation complete!"
echo ""
echo "Scripts installed to: /home/$VPS_USER/bin/"
