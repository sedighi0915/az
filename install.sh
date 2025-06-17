#!/bin/bash

echo "🔄 Updating apt repositories..."
sudo apt update -y

echo "📦 Installing Python3, pip3, and curl..."
sudo apt install -y python3 python3-pip curl

echo "📦 Installing Python packages (colorama, netifaces, requests)..."
python3 -m pip install --break-system-packages --root-user-action=ignore colorama netifaces requests

echo "✅ All done! ✅"
