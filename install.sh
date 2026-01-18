#!/usr/bin/env bash
set -e

echo "=== OCR API INSTALLER (Debian 12 LXC) ==="

### CONFIG
APP_DIR="/opt/ocr"
CONDA_DIR="/opt/miniconda"
ENV_NAME="paddleocr"
SERVICE_NAME="ocr-api"
PORT="8000"

### 0. PRECHECK
if [ "$(id -u)" -ne 0 ]; then
  echo "❌ Jalankan sebagai root"
  exit 1
fi

### 1. STOP & REMOVE OLD SERVICE
echo "[1/9] Cleaning old service..."
systemctl stop ${SERVICE_NAME} 2>/dev/null || true
systemctl disable ${SERVICE_NAME} 2>/dev/null || true
rm -f /etc/systemd/system/${SERVICE_NAME}.service
systemctl daemon-reload

### 2. REMOVE OLD APP & CONDA
echo "[2/9] Removing old installation..."
rm -rf "${APP_DIR}"
rm -rf "${CONDA_DIR}"

### 3. SYSTEM DEPENDENCIES
echo "[3/9] Installing system packages..."
apt update
apt install -y \
  curl wget git \
  build-essential \
  python3 python3-venv \
  tesseract-ocr \
  tesseract-ocr-ind \
  libgl1 \
  libglib2.0-0

### 4. INSTALL MINICONDA
echo "[4/9] Installing Miniconda..."
wget -q https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O /tmp/miniconda.sh
bash /tmp/miniconda.sh -b -p "${CONDA_DIR}"
rm -f /tmp/miniconda.sh

export PATH="${CONDA_DIR}/bin:$PATH"

### 5. CREATE CONDA ENV
echo "[5/9] Creating conda environment..."
conda create -y -n "${ENV_NAME}" python=3.10
source "${CONDA_DIR}/etc/profile.d/conda.sh"
conda activate "${ENV_NAME}"

### 6. PYTHON PACKAGES
echo "[6/9] Installing Python packages..."
pip install --upgrade pip
pip install \
  fastapi \
  uvicorn \
  pillow \
  pytesseract \
  python-multipart

### 7. CREATE APP
echo "[7/9] Creating OCR API..."
mkdir -p "${APP_DIR}"

cat > "${APP_DIR}/app.py" << 'EOF'
from fastapi import FastAPI, File, UploadFile
from PIL import Image
import pytesseract
import io

app = FastAPI()

@app.get("/health")
def health():
    return {"status": "ok"}

@app.post("/ocr")
async def ocr_image(file: UploadFile = File(...)):
    image_bytes = await file.read()
    image = Image.open(io.BytesIO(image_bytes))
    text = pytesseract.image_to_string(image, lang="ind")
    return {
        "filename": file.filename,
        "text": text
    }
EOF

### 8. SYSTEMD SERVICE
echo "[8/9] Creating systemd service..."
cat > /etc/systemd/system/${SERVICE_NAME}.service << EOF
[Unit]
Description=OCR API FastAPI
After=network.target

[Service]
Type=simple
WorkingDirectory=${APP_DIR}
ExecStart=${CONDA_DIR}/envs/${ENV_NAME}/bin/python -m uvicorn app:app --host 0.0.0.0 --port ${PORT}
Restart=always
RestartSec=3
Environment=PATH=${CONDA_DIR}/envs/${ENV_NAME}/bin

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable ${SERVICE_NAME}
systemctl start ${SERVICE_NAME}

### 9. VERIFY
echo "[9/9] Verifying installation..."
sleep 2
systemctl status ${SERVICE_NAME} --no-pager

echo ""
echo "✅ INSTALLATION COMPLETE"
echo "➡ API: http://<IP_LXC>:${PORT}/ocr"
echo "➡ Health: http://<IP_LXC>:${PORT}/health"
