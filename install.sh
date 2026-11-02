#!/usr/bin/env bash

set -e

# Usage: ./install.sh [TARGET]   (TARGET reads .env.remote.TARGET instead of .env.remote)
env_file=.env.remote${1:+.$1}

if [ ! -f "./$env_file" ]; then
    echo "Error: $env_file file not found. Please create one from .env.remote.example"
    exit 1
fi

source "./$env_file"

echo $VPS_IP

if [ -z "$VPS_IP" ] || [ -z "$VPS_USER" ]; then
    echo "Error: VPS_IP and VPS_USER must be set in $env_file"
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

echo "Deploying $env_file to VPS..."
ssh "$VPS_USER@$VPS_IP" "[ -f /home/$VPS_USER/bin/.env ] && cp /home/$VPS_USER/bin/.env /home/$VPS_USER/bin/.env.bak || true"
rsync -v "$env_file" "$VPS_USER@$VPS_IP:/home/$VPS_USER/bin/.env"
echo "Remote .env deployed (previous version backed up as .env.bak if it existed)."

echo ""
echo "Installation complete!"
echo ""
echo "Scripts installed to: /home/$VPS_USER/bin/"
