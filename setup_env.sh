#!/bin/bash
set -e

# Setup Python Virtual Environment
echo "Creating virtual environment 'camera_env'..."
python3 -m venv camera_env

# Activate and install dependencies
source camera_env/bin/activate
echo "Installing dependencies..."
pip install --upgrade pip
pip install -r requirements.txt

echo "Environment setup complete."
